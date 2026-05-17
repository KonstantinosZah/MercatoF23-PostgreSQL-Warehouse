/* ============================================================
   Mercato F23 - PostgreSQL Warehouse
   Script 05: Optional incremental load pattern
   ============================================================

   This script is a conceptual refresh pattern for future source snapshots.

   It assumes a new source file has already been loaded into:
   stg.fact_sales_raw

   Then:
   - stg.v1_fact_sales_typed transforms the new snapshot
   - dimensions are updated with any new members
   - only new fact rows are inserted into dw.fact_sales

   This is not required for the initial portfolio load.
   ============================================================ */


-- ============================================================
-- 1. Insert new customer dimension members
-- ============================================================

INSERT INTO dw.dim_customer (
  customer_id,
  customer_name,
  segment
)
SELECT DISTINCT
  s.customer_id,
  s.customer_name,
  s.segment
FROM stg.v1_fact_sales_typed s
WHERE s.customer_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM dw.dim_customer c
    WHERE c.customer_id = s.customer_id
  );


-- ============================================================
-- 2. Insert new product dimension members
-- ============================================================

INSERT INTO dw.dim_product (
  product_id,
  category,
  sub_category,
  product_name
)
WITH ranked_products AS (
  SELECT
    s.product_id,
    s.category,
    s.sub_category,
    s.product_name,
    ROW_NUMBER() OVER (
      PARTITION BY s.product_id
      ORDER BY COUNT(*) DESC, s.product_name
    ) AS rn
  FROM stg.v1_fact_sales_typed s
  WHERE s.product_id IS NOT NULL
  GROUP BY
    s.product_id,
    s.category,
    s.sub_category,
    s.product_name
)
SELECT
  rp.product_id,
  rp.category,
  rp.sub_category,
  rp.product_name
FROM ranked_products rp
WHERE rp.rn = 1
  AND NOT EXISTS (
    SELECT 1
    FROM dw.dim_product p
    WHERE p.product_id = rp.product_id
  );


-- ============================================================
-- 3. Insert new geography dimension members
-- ============================================================

INSERT INTO dw.dim_geography (
  country,
  region,
  state,
  city,
  postal_code
)
SELECT DISTINCT
  s.country,
  s.region,
  s.state,
  s.city,
  s.postal_code
FROM stg.v1_fact_sales_typed s
WHERE s.country IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM dw.dim_geography g
    WHERE g.country = s.country
      AND g.region = s.region
      AND g.state = s.state
      AND g.city = s.city
      AND g.postal_code = s.postal_code
  );


-- ============================================================
-- 4. Insert new fact rows only
-- ============================================================

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
  s.row_id,
  s.order_id,
  s.order_date,
  s.ship_date,
  s.ship_mode,
  s.customer_id,
  s.product_id,
  g.geography_id,
  s.sales,
  s.quantity,
  s.discount,
  s.profit
FROM stg.v1_fact_sales_typed s
JOIN dw.dim_geography g
  ON g.country = s.country
 AND g.region = s.region
 AND g.state = s.state
 AND g.city = s.city
 AND g.postal_code = s.postal_code
WHERE NOT EXISTS (
  SELECT 1
  FROM dw.fact_sales f
  WHERE f.row_id = s.row_id
);


-- ============================================================
-- 5. Post-load validation
-- ============================================================

SELECT COUNT(*) AS duplicate_row_id_count
FROM sem.v_dq_duplicate_row_ids;

SELECT COUNT(*) AS new_rows_not_loaded_count
FROM sem.v_dq_new_rows_not_loaded;

SELECT
  COUNT(*) AS fact_rows,
  SUM(sales) AS total_sales,
  SUM(profit) AS total_profit
FROM dw.fact_sales;