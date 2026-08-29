-- =====================================================================
-- 03_kpi_queries.sql
-- Olist Customer & Payment Analytics Dashboard
-- ---------------------------------------------------------------------
-- PURPOSE
--   Computes the five headline KPIs of the dashboard.
--
-- METRIC DEFINITIONS (validated against the source data)
--   Total payment value  = SUM(payment_value) over order_payments     (~R$16.0M)
--   Total orders         = COUNT(DISTINCT order_id) in orders         (~99,441)
--   Paid orders          = COUNT(DISTINCT order_id) in order_payments (~99,440)
--   Unique customers     = COUNT(DISTINCT customer_unique_id)         (~96,096)
--   Average order value  = total payment value / paid orders          (~R$161)
--   Delivered orders     = COUNT(DISTINCT order_id) FILTER (order_status='delivered')
--
-- NOTE: numbers below represent the RESULT OF THESE QUERIES on the real
-- dataset, used ONLY as validation benchmarks. Do not hard-code them in
-- the dashboard -- the SQL views (08) reproduce them at runtime.
-- =====================================================================

-- ---------------------------------------------------------------------
-- KPI 1..6 -- single row, all headline KPIs
-- ---------------------------------------------------------------------
SELECT
  (SELECT ROUND(SUM(payment_value)::numeric, 2) FROM order_payments)
                                                              AS total_payment_value,      -- ~16,008,872.12
  (SELECT COUNT(DISTINCT order_id) FROM orders)               AS total_orders,              -- ~99,441
  (SELECT COUNT(DISTINCT order_id) FROM order_payments)       AS paid_orders,               -- ~99,440
  (SELECT COUNT(DISTINCT order_id)
     FROM orders WHERE order_status = 'delivered')            AS delivered_orders,          -- ~96,478
  (SELECT COUNT(DISTINCT customer_unique_id) FROM customers)  AS unique_customers,          -- ~96,096
  (SELECT ROUND(
            (SELECT SUM(payment_value) FROM order_payments)
              / NULLIF((SELECT COUNT(DISTINCT order_id) FROM order_payments), 0)::numeric,
            2))                                               AS average_order_value,       -- ~160.99
  (SELECT ROUND(AVG(review_score)::numeric, 2) FROM order_reviews)
                                                              AS avg_review_score;          -- ~4.09  (see 07)

-- ---------------------------------------------------------------------
-- KPI context -- comparison of the three "money" metrics.
-- They are deliberately different and must never be mixed on the
-- dashboard (see docs/methodology.md).
-- ---------------------------------------------------------------------
SELECT
  'payments.payment_value' AS metric,
  ROUND(SUM(payment_value)::numeric, 2) AS value
FROM order_payments
UNION ALL
SELECT 'order_items.price', ROUND(SUM(price)::numeric, 2)
FROM order_items
UNION ALL
SELECT 'order_items.price + freight_value', ROUND(SUM(price + freight_value)::numeric, 2)
FROM order_items;
-- Expect: ~16,008,872.12  /  ~13,591,643.70  /  ~15,843,553.24
-- =====================================================================