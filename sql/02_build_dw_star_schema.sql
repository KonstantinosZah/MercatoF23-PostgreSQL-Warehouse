/* ============================================================
   Mercato F23 - PostgreSQL Warehouse
   Script 02: Build data warehouse star schema
   ============================================================ */


-- ============================================================
-- 1. Drop existing warehouse tables
-- ============================================================
-- Fact table is dropped first because it depends on the dimensions.

DROP TABLE IF EXISTS dw.fact_sales;
DROP TABLE IF EXISTS dw.dim_geography;
DROP TABLE IF EXISTS dw.dim_customer;
DROP TABLE IF EXISTS dw.dim_product;
DROP TABLE IF EXISTS dw.dim_date;


-- ============================================================
-- 2. Create and load customer dimension
-- ============================================================

CREATE TABLE dw.dim_customer (
  customer_id   text PRIMARY KEY,
  customer_name text,
  segment       text
);

INSERT INTO dw.dim_customer (
  customer_id,
  customer_name,
  segment
)
SELECT DISTINCT
  customer_id,
  customer_name,
  segment
FROM stg.v1_fact_sales_typed
WHERE customer_id IS NOT NULL;


-- ============================================================
-- 3. Create and load product dimension
-- ============================================================
-- Source data quality note:
-- Some product_id values are associated with more than one product_name.
-- To preserve one row per product_id, a deterministic canonical record
-- is selected using the most frequent product_name per product_id.

CREATE TABLE dw.dim_product (
  product_id    text PRIMARY KEY,
  category      text,
  sub_category  text,
  product_name  text
);

INSERT INTO dw.dim_product (
  product_id,
  category,
  sub_category,
  product_name
)
WITH ranked_products AS (
  SELECT
    product_id,
    category,
    sub_category,
    product_name,
    COUNT(*) AS product_row_count,
    ROW_NUMBER() OVER (
      PARTITION BY product_id
      ORDER BY COUNT(*) DESC, product_name
    ) AS rn
  FROM stg.v1_fact_sales_typed
  WHERE product_id IS NOT NULL
  GROUP BY
    product_id,
    category,
    sub_category,
    product_name
)
SELECT
  product_id,
  category,
  sub_category,
  product_name
FROM ranked_products
WHERE rn = 1;


-- ============================================================
-- 4. Create and load geography dimension
-- ============================================================

CREATE TABLE dw.dim_geography (
  geography_id  bigserial PRIMARY KEY,
  country       text,
  region        text,
  state         text,
  city          text,
  postal_code   text,
  CONSTRAINT uq_geo UNIQUE (country, region, state, city, postal_code)
);

INSERT INTO dw.dim_geography (
  country,
  region,
  state,
  city,
  postal_code
)
SELECT DISTINCT
  country,
  region,
  state,
  city,
  postal_code
FROM stg.v1_fact_sales_typed
WHERE country IS NOT NULL;


-- ============================================================
-- 5. Create and load date dimension
-- ============================================================
-- The date dimension is aligned with the Power BI report calendar
-- to support reconciliation of SQL and Power BI KPIs.

CREATE TABLE dw.dim_date (
  date_key        date PRIMARY KEY,
  year            int NOT NULL,
  month_number    int NOT NULL,
  month_name      text NOT NULL,
  quarter         int NOT NULL,
  year_month      int NOT NULL,
  start_of_month  date NOT NULL
);

WITH dates AS (
  SELECT generate_series(
    DATE '2021-01-01',
    DATE '2024-12-31',
    interval '1 day'
  )::date AS d
)
INSERT INTO dw.dim_date (
  date_key,
  year,
  month_number,
  month_name,
  quarter,
  year_month,
  start_of_month
)
SELECT
  d AS date_key,
  EXTRACT(YEAR FROM d)::int AS year,
  EXTRACT(MONTH FROM d)::int AS month_number,
  TO_CHAR(d, 'Mon') AS month_name,
  EXTRACT(QUARTER FROM d)::int AS quarter,
  (EXTRACT(YEAR FROM d)::int * 100 + EXTRACT(MONTH FROM d)::int) AS year_month,
  DATE_TRUNC('month', d)::date AS start_of_month
FROM dates;


-- ============================================================
-- 6. Create and load fact table
-- ============================================================
-- Fact grain:
-- 1 row = 1 sales line item.
--
-- order_date references dim_date because it is the active reporting date.
-- ship_date is kept as a date column without a foreign key because a small
-- number of shipments spill into early 2025 while the Power BI calendar
-- intentionally ends on 2024-12-31.

CREATE TABLE dw.fact_sales (
  row_id        int PRIMARY KEY,
  order_id      text NOT NULL,

  order_date    date NOT NULL REFERENCES dw.dim_date(date_key),
  ship_date     date NOT NULL,

  ship_mode     text,

  customer_id   text NOT NULL REFERENCES dw.dim_customer(customer_id),
  product_id    text NOT NULL REFERENCES dw.dim_product(product_id),
  geography_id  bigint NOT NULL REFERENCES dw.dim_geography(geography_id),

  sales         numeric(18,4) NOT NULL,
  quantity      int NOT NULL,
  discount      numeric(6,4) NOT NULL,
  profit        numeric(18,4) NOT NULL
);

INSERT INTO dw.fact_sales (
  row_id,
  order_id,
  order_date,
  ship_date,
  ship_mode,
  customer_id,
  product_id,
  geography_id,
  sales,
  quantity,
  discount,
  profit
)
SELECT
  fst.row_id,
  fst.order_id,
  fst.order_date,
  fst.ship_date,
  fst.ship_mode,
  fst.customer_id,
  fst.product_id,
  dg.geography_id,
  fst.sales,
  fst.quantity,
  fst.discount,
  fst.profit
FROM stg.v1_fact_sales_typed fst
JOIN dw.dim_geography dg
  ON dg.country = fst.country
 AND dg.region = fst.region
 AND dg.state = fst.state
 AND dg.city = fst.city
 AND dg.postal_code = fst.postal_code;


-- ============================================================
-- 7. Basic warehouse validation
-- ============================================================

-- Row count reconciliation: staging vs fact
SELECT
  (SELECT COUNT(*) FROM stg.v1_fact_sales_typed) AS staging_rows,
  (SELECT COUNT(*) FROM dw.fact_sales) AS fact_rows;

-- Dimension counts
SELECT COUNT(*) AS customer_count
FROM dw.dim_customer;

SELECT COUNT(*) AS product_count
FROM dw.dim_product;

SELECT COUNT(*) AS geography_count
FROM dw.dim_geography;

SELECT COUNT(*) AS date_count
FROM dw.dim_date;

-- Date dimension boundaries
SELECT
  MIN(date_key) AS min_date,
  MAX(date_key) AS max_date,
  COUNT(*) AS date_rows
FROM dw.dim_date;

-- Fact primary key validation
SELECT
  COUNT(*) - COUNT(DISTINCT row_id) AS duplicate_row_ids
FROM dw.fact_sales;

-- Geography mapping validation
SELECT COUNT(*) AS missing_geography_matches
FROM stg.v1_fact_sales_typed fst
LEFT JOIN dw.dim_geography dg
  ON dg.country = fst.country
 AND dg.region = fst.region
 AND dg.state = fst.state
 AND dg.city = fst.city
 AND dg.postal_code = fst.postal_code
WHERE dg.geography_id IS NULL;


-- ============================================================
-- 8. KPI reconciliation checkpoint
-- ============================================================

SELECT
  SUM(sales) AS total_sales,
  SUM(profit) AS total_profit,
  COUNT(DISTINCT order_id) AS total_orders,
  COUNT(DISTINCT customer_id) AS active_customers
FROM dw.fact_sales;