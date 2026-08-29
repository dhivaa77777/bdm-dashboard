-- =====================================================================
-- 05_customer_analysis.sql
-- Olist Customer & Payment Analytics Dashboard
-- ---------------------------------------------------------------------
-- PURPOSE
--   Customer value and geography: top customers by spend and top states
--   by payment value.
--
-- GRAIN WARNINGS
--   * Customers are identified by customer_unique_id (NOT customer_id),
--     because one person can own several customer_ids. See check 2/5.
--   * payments must be aggregated before any 1-to-many join. Here we go
--     straight from order_payments -> orders -> customers, which is safe
--     for spending because order_payments is the money source and
--     orders/customers are 1-to-1 with it.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TOP 5 CUSTOMERS BY TOTAL SPEND
--    customer_id is masked on the dashboard for privacy; aggregation is
--    by unique customer.
-- ---------------------------------------------------------------------
SELECT
  c.customer_unique_id,
  COUNT(DISTINCT o.order_id)            AS order_count,
  ROUND(SUM(p.payment_value)::numeric, 2) AS total_spend,
  ROUND((SUM(p.payment_value) / NULLIF(COUNT(DISTINCT o.order_id), 0))::numeric, 2)
                                        AS avg_order_value
FROM order_payments p
JOIN orders o    ON o.order_id = p.order_id
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
ORDER BY total_spend DESC
LIMIT 5;
-- Benchmarks (real data, spend):
--   1. R$13,664.08 (1 order, RJ)   2. R$9,553.02 (3 orders, SC)
--   3. R$7,571.63 (2 orders, RJ)   4. R$7,274.88 (1 order, ES)
--   5. R$6,929.31 (1 order, MS)

-- ---------------------------------------------------------------------
-- 2. CUSTOMER CONCENTRATION -- the analytically important number.
--    The top 5 customers are TINY relative to the total: this is a
--    highly distributed B2C customer base, not a business dependent on
--    a few accounts. This is the insight shown next to the list.
-- ---------------------------------------------------------------------
SELECT
  ROUND(100.0 *
        (SELECT SUM(total_spend)
         FROM (SELECT SUM(p.payment_value) AS total_spend
               FROM order_payments p
               JOIN orders o ON o.order_id = p.order_id
               JOIN customers c ON c.customer_id = o.customer_id
               GROUP BY c.customer_unique_id
               ORDER BY total_spend DESC
               LIMIT 5) top5) /
        (SELECT SUM(payment_value) FROM order_payments), 2) AS top5_customer_share_pct;
-- Benchmark: 0.28%

-- ---------------------------------------------------------------------
-- 3. TOP 5 CUSTOMER STATES BY PAYMENT VALUE
-- ---------------------------------------------------------------------
SELECT
  c.customer_state,
  COUNT(DISTINCT c.customer_unique_id) AS customers,
  COUNT(DISTINCT o.order_id)            AS orders,
  ROUND(SUM(p.payment_value)::numeric, 2) AS total_payment_value
FROM order_payments p
JOIN orders o    ON o.order_id = p.order_id
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY c.customer_state
ORDER BY total_payment_value DESC
LIMIT 5;
-- Benchmarks (real data):
--   SP 40,301 customers | 41,745 orders | R$5,998,226.96
--   RJ 12,384 customers | 12,852 orders | R$2,144,379.69
--   MG 11,259 customers | 11,635 orders | R$1,872,257.26
--   RS  5,277 customers |  5,466 orders | R$  890,898.54
--   PR  4,882 customers |  5,045 orders | R$  811,156.38

-- ---------------------------------------------------------------------
-- 4. STATE CONCENTRATION (goes on the dashboard as one insight)
-- ---------------------------------------------------------------------
SELECT
  ROUND(100.0 *
        (SELECT SUM(total_payment_value)
         FROM (SELECT SUM(p.payment_value) AS total_payment_value
               FROM order_payments p
               JOIN orders o ON o.order_id = p.order_id
               JOIN customers c ON c.customer_id = o.customer_id
               GROUP BY c.customer_state
               ORDER BY total_payment_value DESC
               LIMIT 5) top5) /
        (SELECT SUM(payment_value) FROM order_payments), 2) AS top5_state_share_pct;
-- Benchmark: 73.19%
-- =====================================================================