-- =====================================================================
-- 04_payment_analysis.sql
-- Olist Customer & Payment Analytics Dashboard
-- ---------------------------------------------------------------------
-- PURPOSE
--   Payment behaviour: how customers pay and how they use installments.
--   This is the PRIMARY section of the dashboard (staff requirement).
--
-- GRAIN WARNING
--   order_payments has ONE ROW PER (order_id, payment_sequential). For
--   "orders that used method X" we COUNT(DISTINCT order_id); for money
--   we SUM(payment_value) at the payment grain. Shares use window
--   functions so they always total 100% of the correct base.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PAYMENT TYPE PIVOT (the main payment visual)
-- ---------------------------------------------------------------------
SELECT
  payment_type,
  COUNT(DISTINCT order_id)                          AS orders,
  ROUND(SUM(payment_value)::numeric, 2)             AS total_payment_value,
  ROUND(100.0 * SUM(payment_value) / NULLIF(SUM(SUM(payment_value)) OVER (), 0), 2)
                                                    AS value_share_pct,
  ROUND(100.0 * COUNT(DISTINCT order_id)
        / NULLIF(SUM(COUNT(DISTINCT order_id)) OVER (), 0), 2)
                                                    AS order_share_pct
FROM order_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;
-- Benchmarks (real data):
--   credit_card  76,505 orders  R$12,542,084.19  78.34% value
--   boleto       19,784 orders  R$ 2,869,361.27  17.92% value
--   voucher       3,866 orders  R$   379,436.87   2.37% value
--   debit_card    1,528 orders  R$   217,989.79   1.36% value
--   not_defined       3 orders  R$         0.00   0.00% value -> excluded visually

-- ---------------------------------------------------------------------
-- 2. INSTALLMENT SUMMARY (top patterns only for the dashboard)
-- ---------------------------------------------------------------------
SELECT
  payment_installments,
  COUNT(DISTINCT order_id) AS orders,
  ROUND(SUM(payment_value)::numeric, 2) AS total_payment_value,
  ROUND(100.0 * COUNT(DISTINCT order_id)
        / NULLIF((SELECT COUNT(DISTINCT order_id) FROM order_payments), 0), 2)
                                    AS order_share_pct
FROM order_payments
GROUP BY payment_installments
ORDER BY orders DESC
LIMIT 8;
-- Benchmarks: 1x -> 49,060 orders (49.3%); 2x -> 12,389 (12.5%);
--             3x -> 10,443 (10.5%); 4x -> 7,088 (7.1%); 10x -> 5,315 (5.3%);
--             5x -> 5,234 (5.3%); 8x -> 4,253 (4.3%); 6x -> 3,916 (3.9%).

-- ---------------------------------------------------------------------
-- 3. INSTALLMENT USAGE (share of orders paid on credit, >1 installment)
-- ---------------------------------------------------------------------
SELECT
  COUNT(DISTINCT order_id)                                                        AS paid_orders,
  COUNT(DISTINCT order_id) FILTER (WHERE payment_installments > 1)                AS installment_orders,
  ROUND(100.0 * COUNT(DISTINCT order_id) FILTER (WHERE payment_installments > 1)
        / NULLIF(COUNT(DISTINCT order_id), 0), 2)                                 AS installment_order_pct
FROM order_payments;
-- Benchmark: 51,170 orders / 99,440 = 51.5% of paid orders use installments.

-- ---------------------------------------------------------------------
-- 4. AVG PAYMENT PER TYPE (value context)
-- ---------------------------------------------------------------------
SELECT
  payment_type,
  ROUND(AVG(payment_value)::numeric, 2)               AS avg_payment_value,
  ROUND(MAX(payment_value)::numeric, 2)               AS max_payment_value
FROM order_payments
GROUP BY payment_type
ORDER BY avg_payment_value DESC;
-- =====================================================================