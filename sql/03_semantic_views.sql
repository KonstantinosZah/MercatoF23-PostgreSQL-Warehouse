/* ============================================================
   Mercato F23 - PostgreSQL Warehouse
   Script 03: Create semantic layer views
   ============================================================ */


-- ============================================================
-- 1. Drop existing semantic views
-- ============================================================
-- Dependent views are dropped first.

DROP VIEW IF EXISTS sem.v_kpi_top20pct_customers_sales_share;
DROP VIEW IF EXISTS sem.v_customer_sales_ranked;
DROP VIEW IF EXISTS sem.v_geography_sales;
DROP VIEW IF EXISTS sem.v_product_sales;
DROP VIEW IF EXISTS sem.v_customer_sales;
DROP VIEW IF EXISTS sem.v_seasonality_avg_monthly_sales;
DROP VIEW IF EXISTS sem.v_sales_monthly_ma;
DROP VIEW IF EXISTS sem.v_sales_monthly_yoy;
DROP VIEW IF EXISTS sem.v_sales_monthly;


-- ============================================================
-- 2. Monthly sales view
-- ============================================================
-- Grain: one row per month, based on order_date.

CREATE OR REPLACE VIEW sem.v_sales_monthly AS
SELECT
  d.start_of_month,
  d.year,
  d.month_number,
  d.month_name,
  d.year_month,

  SUM(f.sales)      AS sales,
  SUM(f.profit)     AS profit,
  SUM(f.quantity)   AS quantity,
  AVG(f.discount)   AS avg_discount,

  COUNT(DISTINCT f.order_id)      AS orders,
  COUNT(DISTINCT f.customer_id)   AS customers,
  COUNT(DISTINCT f.product_id)    AS products,

  SUM(f.profit) / NULLIF(SUM(f.sales), 0) AS profit_margin
FROM dw.dim_date d
JOIN dw.fact_sales f
  ON d.date_key = f.order_date
GROUP BY
  d.start_of_month,
  d.year,
  d.month_number,
  d.month_name,
  d.year_month;


-- ============================================================
-- 3. Monthly YoY view
-- ============================================================
-- Adds last-year metrics and YoY percentage changes.

CREATE OR REPLACE VIEW sem.v_sales_monthly_yoy AS
SELECT
  m.*,

  LAG(m.sales, 12)         OVER (ORDER BY m.start_of_month) AS sales_ly,
  LAG(m.profit, 12)        OVER (ORDER BY m.start_of_month) AS profit_ly,
  LAG(m.orders, 12)        OVER (ORDER BY m.start_of_month) AS orders_ly,
  LAG(m.customers, 12)     OVER (ORDER BY m.start_of_month) AS customers_ly,
  LAG(m.profit_margin, 12) OVER (ORDER BY m.start_of_month) AS profit_margin_ly,

  (m.sales - LAG(m.sales, 12) OVER (ORDER BY m.start_of_month))
    / NULLIF(LAG(m.sales, 12) OVER (ORDER BY m.start_of_month), 0) AS sales_yoy_pct,

  (m.profit - LAG(m.profit, 12) OVER (ORDER BY m.start_of_month))
    / NULLIF(LAG(m.profit, 12) OVER (ORDER BY m.start_of_month), 0) AS profit_yoy_pct,

  (m.orders - LAG(m.orders, 12) OVER (ORDER BY m.start_of_month))
    / NULLIF(LAG(m.orders, 12) OVER (ORDER BY m.start_of_month), 0)::numeric AS orders_yoy_pct,

  (m.customers - LAG(m.customers, 12) OVER (ORDER BY m.start_of_month))
    / NULLIF(LAG(m.customers, 12) OVER (ORDER BY m.start_of_month), 0)::numeric AS customers_yoy_pct,

  m.profit_margin - LAG(m.profit_margin, 12) OVER (ORDER BY m.start_of_month)
    AS profit_margin_delta
FROM sem.v_sales_monthly m;


-- ============================================================
-- 4. Monthly moving averages view
-- ============================================================
-- Adds 3-month and 6-month moving averages for sales and profit.

CREATE OR REPLACE VIEW sem.v_sales_monthly_ma AS
SELECT
  m.*,

  AVG(m.sales) OVER (
    ORDER BY m.start_of_month
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
  ) AS sales_ma3,

  AVG(m.sales) OVER (
    ORDER BY m.start_of_month
    ROWS BETWEEN 5 PRECEDING AND CURRENT ROW
  ) AS sales_ma6,

  AVG(m.profit) OVER (
    ORDER BY m.start_of_month
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
  ) AS profit_ma3,

  AVG(m.profit) OVER (
    ORDER BY m.start_of_month
    ROWS BETWEEN 5 PRECEDING AND CURRENT ROW
  ) AS profit_ma6
FROM sem.v_sales_monthly m;


-- ============================================================
-- 5. Seasonality view
-- ============================================================
-- Grain: one row per month-of-year.
-- Metric: average monthly sales across years.

CREATE OR REPLACE VIEW sem.v_seasonality_avg_monthly_sales AS
SELECT
  month_number,
  MIN(month_name) AS month_name,
  AVG(sales) AS avg_monthly_sales
FROM sem.v_sales_monthly
GROUP BY month_number;


-- ============================================================
-- 6. Customer sales view
-- ============================================================
-- Grain: one row per customer.

CREATE OR REPLACE VIEW sem.v_customer_sales AS
SELECT
  c.customer_id,
  c.customer_name,
  c.segment,

  SUM(f.sales)      AS sales,
  SUM(f.profit)     AS profit,
  SUM(f.quantity)   AS quantity,
  AVG(f.discount)   AS avg_discount,

  COUNT(DISTINCT f.order_id)    AS orders,
  COUNT(DISTINCT f.product_id)  AS products,

  SUM(f.sales) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS avg_sales_per_order,
  SUM(f.profit) / NULLIF(SUM(f.sales), 0) AS profit_margin
FROM dw.dim_customer c
JOIN dw.fact_sales f
  ON c.customer_id = f.customer_id
GROUP BY
  c.customer_id,
  c.customer_name,
  c.segment;


-- ============================================================
-- 7. Customer Pareto ranking view
-- ============================================================
-- Adds customer rank, individual sales share, cumulative sales share,
-- and customer percentile rank.

CREATE OR REPLACE VIEW sem.v_customer_sales_ranked AS
WITH base_table AS (
  SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY sales DESC) AS customer_rank,
    COUNT(*) OVER () AS total_customers,
    SUM(sales) OVER () AS total_sales
  FROM sem.v_customer_sales
)
SELECT
  *,
  sales / NULLIF(total_sales, 0) AS sales_share,
  SUM(sales) OVER (
    ORDER BY customer_rank
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) / NULLIF(total_sales, 0) AS cum_sales_share,
  customer_rank::numeric / NULLIF(total_customers, 0) AS customer_pct_rank
FROM base_table;


-- ============================================================
-- 8. Top 20% customers sales share KPI
-- ============================================================

CREATE OR REPLACE VIEW sem.v_kpi_top20pct_customers_sales_share AS
SELECT
  MAX(cum_sales_share) AS top20pct_customers_sales_share
FROM sem.v_customer_sales_ranked
WHERE customer_pct_rank <= 0.20;


-- ============================================================
-- 9. Product sales view
-- ============================================================
-- Grain: one row per product.

CREATE OR REPLACE VIEW sem.v_product_sales AS
SELECT
  p.product_id,
  p.category,
  p.sub_category,
  p.product_name,

  SUM(f.sales)      AS sales,
  SUM(f.profit)     AS profit,
  SUM(f.quantity)   AS quantity,
  AVG(f.discount)   AS avg_discount,

  COUNT(DISTINCT f.order_id)    AS orders,
  COUNT(DISTINCT f.customer_id) AS customers,

  SUM(f.sales) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS avg_sales_per_order,
  SUM(f.profit) / NULLIF(SUM(f.sales), 0) AS profit_margin
FROM dw.dim_product p
JOIN dw.fact_sales f
  ON p.product_id = f.product_id
GROUP BY
  p.product_id,
  p.category,
  p.sub_category,
  p.product_name;


-- ============================================================
-- 10. Geography sales view
-- ============================================================
-- Grain: one row per geography.

CREATE OR REPLACE VIEW sem.v_geography_sales AS
SELECT
  g.geography_id,
  g.country,
  g.region,
  g.state,
  g.city,
  g.postal_code,

  SUM(f.sales)      AS sales,
  SUM(f.profit)     AS profit,
  SUM(f.quantity)   AS quantity,
  AVG(f.discount)   AS avg_discount,

  COUNT(DISTINCT f.order_id)    AS orders,
  COUNT(DISTINCT f.customer_id) AS customers,

  SUM(f.profit) / NULLIF(SUM(f.sales), 0) AS profit_margin
FROM dw.dim_geography g
JOIN dw.fact_sales f
  ON g.geography_id = f.geography_id
GROUP BY
  g.geography_id,
  g.country,
  g.region,
  g.state,
  g.city,
  g.postal_code;


-- ============================================================
-- 11. Semantic layer validation checks
-- ============================================================

-- Monthly view reconciliation
SELECT
  (SELECT SUM(sales) FROM dw.fact_sales) AS fact_sales,
  (SELECT SUM(sales) FROM sem.v_sales_monthly) AS monthly_sales,
  (SELECT SUM(profit) FROM dw.fact_sales) AS fact_profit,
  (SELECT SUM(profit) FROM sem.v_sales_monthly) AS monthly_profit;

-- Customer view reconciliation
SELECT
  COUNT(*) AS customer_rows,
  SUM(sales) AS customer_sales,
  SUM(profit) AS customer_profit
FROM sem.v_customer_sales;

-- Product view reconciliation
SELECT
  COUNT(*) AS product_rows,
  SUM(sales) AS product_sales,
  SUM(profit) AS product_profit
FROM sem.v_product_sales;

-- Geography view reconciliation
SELECT
  COUNT(*) AS geography_rows,
  SUM(sales) AS geography_sales,
  SUM(profit) AS geography_profit
FROM sem.v_geography_sales;

-- Sample YoY output
SELECT
  start_of_month,
  sales,
  sales_ly,
  sales_yoy_pct,
  orders,
  orders_ly,
  orders_yoy_pct,
  profit_margin,
  profit_margin_ly,
  profit_margin_delta
FROM sem.v_sales_monthly_yoy
ORDER BY start_of_month DESC
LIMIT 20;

-- Sample moving-average output
SELECT
  start_of_month,
  sales,
  sales_ma3,
  sales_ma6,
  profit,
  profit_ma3,
  profit_ma6
FROM sem.v_sales_monthly_ma
ORDER BY start_of_month
LIMIT 12;

-- Customer Pareto KPI
SELECT *
FROM sem.v_kpi_top20pct_customers_sales_share;