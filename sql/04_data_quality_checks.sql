/* ============================================================
   Mercato F23 - PostgreSQL Warehouse
   Script 04: Data quality checks and reconciliation queries
   ============================================================ */


-- ============================================================
-- 1. Semantic view reconciliation checks
-- ============================================================
-- These checks validate that semantic-layer aggregates reconcile
-- back to the warehouse fact table.

-- Monthly view reconciliation
SELECT
  (SELECT SUM(sales) FROM dw.fact_sales) AS fact_sales,
  (SELECT SUM(sales) FROM sem.v_sales_monthly) AS monthly_sales,
  (SELECT SUM(profit) FROM dw.fact_sales) AS fact_profit,
  (SELECT SUM(profit) FROM sem.v_sales_monthly) AS monthly_profit;

-- Customer view reconciliation
SELECT
  (SELECT SUM(sales) FROM dw.fact_sales) AS fact_sales,
  (SELECT SUM(sales) FROM sem.v_customer_sales) AS customer_sales,
  (SELECT SUM(profit) FROM dw.fact_sales) AS fact_profit,
  (SELECT SUM(profit) FROM sem.v_customer_sales) AS customer_profit;

-- Product view reconciliation
SELECT
  (SELECT SUM(sales) FROM dw.fact_sales) AS fact_sales,
  (SELECT SUM(sales) FROM sem.v_product_sales) AS product_sales,
  (SELECT SUM(profit) FROM dw.fact_sales) AS fact_profit,
  (SELECT SUM(profit) FROM sem.v_product_sales) AS product_profit;

-- Geography view reconciliation
SELECT
  (SELECT SUM(sales) FROM dw.fact_sales) AS fact_sales,
  (SELECT SUM(sales) FROM sem.v_geography_sales) AS geography_sales,
  (SELECT SUM(profit) FROM dw.fact_sales) AS fact_profit,
  (SELECT SUM(profit) FROM sem.v_geography_sales) AS geography_profit;


-- ============================================================
-- 2. Data quality audit views
-- ============================================================

-- Identifies duplicate row_id values in the typed staging layer.
-- Expected result: 0 rows.
CREATE OR REPLACE VIEW sem.v_dq_duplicate_row_ids AS
SELECT
  row_id,
  COUNT(*) AS row_count
FROM stg.v1_fact_sales_typed
GROUP BY row_id
HAVING COUNT(*) > 1;


-- Identifies staging rows that have not been loaded to the warehouse fact table.
-- Expected result: 0 rows after a successful load.
CREATE OR REPLACE VIEW sem.v_dq_new_rows_not_loaded AS
SELECT
  s.row_id,
  s.order_id,
  s.order_date,
  s.customer_id,
  s.product_id,
  s.sales,
  s.profit
FROM stg.v1_fact_sales_typed s
LEFT JOIN dw.fact_sales f
  ON f.row_id = s.row_id
WHERE f.row_id IS NULL;


-- ============================================================
-- 3. Data quality check results
-- ============================================================

SELECT COUNT(*) AS duplicate_row_id_count
FROM sem.v_dq_duplicate_row_ids;

SELECT COUNT(*) AS new_rows_not_loaded_count
FROM sem.v_dq_new_rows_not_loaded;


-- ============================================================
-- 4. Optional sample inspection queries
-- ============================================================

SELECT *
FROM sem.v_dq_duplicate_row_ids;

SELECT *
FROM sem.v_dq_new_rows_not_loaded;