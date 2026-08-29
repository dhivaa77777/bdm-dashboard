-- =====================================================================
-- 02_data_quality_checks.sql
-- Olist Customer & Payment Analytics Dashboard
-- ---------------------------------------------------------------------
-- PURPOSE
--   Verifies the loaded data before any analysis is trusted. Each block
--   prints a count.  EXPECTED results (real dataset) are noted inline;
--   if a check deviates from the expectation, stop and fix the load
--   before running 03..08.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ROW COUNTS PER TABLE
-- ---------------------------------------------------------------------
SELECT 'customers' AS table_name, COUNT(*) AS rows FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM product_category_name_translation
ORDER BY table_name;
-- Expect: 99,441 / 99,441 / 112,650 / 103,886 / 99,224 / 32,951 / 3,095 / ~1,000,163 / 71

-- ---------------------------------------------------------------------
-- 2. NULL CHECKS ON CRITICAL COLUMNS
-- ---------------------------------------------------------------------
SELECT
  COUNT(*) FILTER (WHERE customer_unique_id IS NULL) AS nulls_customer_unique,
  COUNT(DISTINCT customer_unique_id)                AS distinct_customers
FROM customers;
-- Expect: 0 nulls; 96,096 distinct (fewer than 99,441 rows -> some people
--         repeat across orders; this is expected and why we analyse by
--         customer_unique_id).

SELECT
  COUNT(*)                                             AS payment_rows,
  COUNT(DISTINCT order_id)                             AS paid_orders,
  COUNT(*) FILTER (WHERE payment_value IS NULL)        AS nulls_value,
  COUNT(*) FILTER (WHERE payment_value <= 0)           AS non_positive_value,
  COUNT(*) FILTER (WHERE payment_type IS NULL)         AS nulls_type
FROM order_payments;
-- Expect: 103,886 rows; 99,440 paid orders; 0 nulls; 9 zero-value rows
-- (voucher / not_defined entries worth 0.00 -- harmless, no negative values);
-- 0 nulls type.

-- List the zero-value payment rows (all are 0.00 vouchers/not_defined).
SELECT order_id, payment_sequential, payment_type, payment_value
FROM order_payments
WHERE payment_value <= 0
ORDER BY payment_type;

SELECT
  COUNT(*)                                        AS item_rows,
  COUNT(DISTINCT order_id)                        AS item_orders,
  COUNT(*) FILTER (WHERE price IS NULL)           AS nulls_price,
  COUNT(*) FILTER (WHERE price < 0)               AS negative_price
FROM order_items;
-- Expect: 112,650 rows; 98,666 distinct orders with items; 0 null price.

-- ---------------------------------------------------------------------
-- 3. PRIMARY-KEY / DUPLICATE CHECKS
-- ---------------------------------------------------------------------
SELECT order_id, COUNT(*) AS dupes
FROM orders GROUP BY order_id HAVING COUNT(*) > 1;
-- Expect: 0 rows.

SELECT order_id, payment_sequential, COUNT(*) AS dupes
FROM order_payments GROUP BY order_id, payment_sequential HAVING COUNT(*) > 1;
-- Expect: 0 rows.

SELECT order_id, order_item_id, COUNT(*) AS dupes
FROM order_items GROUP BY order_id, order_item_id HAVING COUNT(*) > 1;
-- Expect: 0 rows.

-- ---------------------------------------------------------------------
-- 4. GRAIN CHECKS -- ORDER PAYMENTS (THE MOST CRITICAL CHECK)
--    An order can have several payment rows. Understanding this grain
--    prevents every double-counting bug downstream.
-- ---------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM order_payments)                      AS total_payment_rows,
  (SELECT COUNT(DISTINCT order_id) FROM order_payments)      AS total_paid_orders,
  (SELECT COUNT(*) FROM order_payments)
    - (SELECT COUNT(DISTINCT order_id) FROM order_payments)  AS extra_payment_rows,
  (SELECT COUNT(*) FROM (
     SELECT order_id FROM order_payments GROUP BY order_id HAVING COUNT(*) > 1
   ) m)                                                      AS orders_with_multiple_payment_rows;
-- Expect: 103,886 rows; 99,440 paid orders; 4,446 extra rows; 2,961 orders
--         carrying more than one payment row.

-- Split payments: orders paid using more than one payment_type.
SELECT COUNT(*) AS split_payment_orders FROM (
  SELECT order_id
  FROM order_payments
  GROUP BY order_id
  HAVING COUNT(DISTINCT payment_type) > 1
) sub;
-- Expect: 2,246.

-- ---------------------------------------------------------------------
-- 5. CUSTOMER GRAIN CHECK
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS repeat_customers FROM (
  SELECT customer_unique_id
  FROM customers
  GROUP BY customer_unique_id
  HAVING COUNT(*) > 1
) sub;
-- Expect: 2,997 unique customers appear under more than one customer_id
--         (their extra customer_ids account for the 99,441 - 96,096 gap).

-- ---------------------------------------------------------------------
-- 6. ORDERS WITHOUT PAYMENT / PAYMENT WITHOUT ORDER (orphans)
-- ---------------------------------------------------------------------
-- Orders that have NO payment records at all.
SELECT COUNT(*) AS orders_without_payment
FROM orders o
LEFT JOIN order_payments p ON o.order_id = p.order_id
WHERE p.order_id IS NULL;
-- Expect: 1 (single order missing from payments; flag it for the load).

-- Payment rows with no matching order (should never happen thanks to FK).
SELECT COUNT(*) AS orphan_payments
FROM order_payments p LEFT JOIN orders o ON o.order_id = p.order_id
WHERE o.order_id IS NULL;
-- Expect: 0.

-- Items with no matching order.
SELECT COUNT(*) AS orphan_items
FROM order_items i LEFT JOIN orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL;
-- Expect: 0.

-- ---------------------------------------------------------------------
-- 7. ORDER STATUS DISTRIBUTION
-- ---------------------------------------------------------------------
SELECT order_status, COUNT(*) AS orders, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM orders GROUP BY order_status ORDER BY orders DESC;
-- Expect: delivered 96,478 (97.02%); shipped 1,107; canceled 625;
--         unavailable 609; invoiced 314; processing 301; created 5; approved 2.

-- ---------------------------------------------------------------------
-- 8. PAYMENT TYPE DOMAIN VALUES
-- ---------------------------------------------------------------------
SELECT payment_type, COUNT(*) AS rows
FROM order_payments GROUP BY payment_type ORDER BY rows DESC;
-- Expect: credit_card, boleto, voucher, debit_card, plus 0-value
--         'not_defined' rows (kept for completeness, excluded from value
--         rankings because their value is 0).

-- ---------------------------------------------------------------------
-- 9. REVIEW SCORE RANGE + DUPLICATE REVIEWS
--    review_id is intentionally NOT a PK (source quirk: 789 review_id
--    values are reused across different orders). The grain is one review
--    row per order occurrence, keyed by order_id.
-- ---------------------------------------------------------------------
SELECT MIN(review_score) AS min_score, MAX(review_score) AS max_score
FROM order_reviews;
-- Expect: 1 and 5.

-- How many review_id values are reused for more than one order?
SELECT COUNT(*) AS reused_review_ids FROM (
  SELECT review_id
  FROM order_reviews
  GROUP BY review_id
  HAVING COUNT(DISTINCT order_id) > 1
) sub;
-- Expect: 789.

-- Sample of reused ids (different order_ids, same content).
SELECT review_id, COUNT(DISTINCT order_id) AS orders
FROM order_reviews
GROUP BY review_id
HAVING COUNT(DISTINCT order_id) > 1
ORDER BY orders DESC
LIMIT 5;

-- No review row should point at the same order more than once
-- (duplicate review submissions for the SAME order would be a defect).
SELECT COUNT(*) FROM (
  SELECT review_id, order_id
  FROM order_reviews
  GROUP BY review_id, order_id
  HAVING COUNT(*) > 1
) sub;
-- Expect: 0.
-- =====================================================================