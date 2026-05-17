/* ============================================================
   Mercato F23 - PostgreSQL Warehouse
   Script 01: Create schemas, staging table, and typed staging view
   ============================================================ */


-- ============================================================
-- 1. Create schemas
-- ============================================================

CREATE SCHEMA IF NOT EXISTS stg;
CREATE SCHEMA IF NOT EXISTS dw;
CREATE SCHEMA IF NOT EXISTS sem;


-- ============================================================
-- 2. Create raw staging table
-- ============================================================
-- Raw CSV values are loaded as text to avoid import failures
-- from date parsing, decimal precision, encoding, or quoting issues.

DROP TABLE IF EXISTS stg.fact_sales_raw;

CREATE TABLE stg.fact_sales_raw (
  row_id text,
  order_id text,
  order_date text,
  ship_date text,
  ship_mode text,
  customer_id text,
  customer_name text,
  segment text,
  country text,
  city text,
  state text,
  postal_code text,
  region text,
  product_id text,
  category text,
  sub_category text,
  product_name text,
  sales text,
  quantity text,
  discount text,
  profit text
);


-- ============================================================
-- 3. Load CSV into raw staging table
-- ============================================================
-- Replace the file path below with the local CSV path.

-- COPY stg.fact_sales_raw (
--   row_id, order_id, order_date, ship_date, ship_mode,
--   customer_id, customer_name, segment,
--   country, city, state, postal_code, region,
--   product_id, category, sub_category, product_name,
--   sales, quantity, discount, profit
-- )
-- FROM 'C:/path/to/SampleSuperstore.csv'
-- WITH (
--   FORMAT csv,
--   HEADER true,
--   DELIMITER ',',
--   QUOTE '"',
--   ESCAPE '"',
--   ENCODING 'UTF8'
-- );


-- ============================================================
-- 4. Validate raw staging load
-- ============================================================

SELECT COUNT(*) AS raw_rows
FROM stg.fact_sales_raw;

SELECT
  MIN(order_date) AS min_order_date_raw,
  MAX(order_date) AS max_order_date_raw
FROM stg.fact_sales_raw;

SELECT *
FROM stg.fact_sales_raw
LIMIT 20;


-- ============================================================
-- 5. Create typed staging view
-- ============================================================
-- This view applies the same conceptual cleaning steps used in Power Query:
-- - Parse US-format dates
-- - Shift original years forward by +7 years
-- - Cast numeric measures using sufficient precision

DROP VIEW IF EXISTS stg.v1_fact_sales_typed;

CREATE VIEW stg.v1_fact_sales_typed AS
SELECT
  row_id::int AS row_id,
  order_id,

  (to_date(order_date, 'MM/DD/YYYY') + interval '7 years')::date AS order_date,
  (to_date(ship_date,  'MM/DD/YYYY') + interval '7 years')::date AS ship_date,

  ship_mode,
  customer_id,
  customer_name,
  segment,
  country,
  city,
  state,
  postal_code,
  region,
  product_id,
  category,
  sub_category,
  product_name,

  sales::numeric(18,4)    AS sales,
  quantity::int           AS quantity,
  discount::numeric(6,4)  AS discount,
  profit::numeric(18,4)   AS profit
FROM stg.fact_sales_raw;


-- ============================================================
-- 6. Validate typed staging view
-- ============================================================

SELECT
  MIN(order_date) AS min_order_date,
  MAX(order_date) AS max_order_date,
  MIN(ship_date)  AS min_ship_date,
  MAX(ship_date)  AS max_ship_date
FROM stg.v1_fact_sales_typed;

SELECT
  MIN(sales) AS min_sales,
  MAX(sales) AS max_sales,
  SUM(sales) AS total_sales
FROM stg.v1_fact_sales_typed;

SELECT
  pg_typeof(sales)  AS sales_type,
  pg_typeof(profit) AS profit_type
FROM stg.v1_fact_sales_typed
LIMIT 1;