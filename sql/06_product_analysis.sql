-- =====================================================================
-- 06_product_analysis.sql
-- Olist Customer & Payment Analytics Dashboard
-- ---------------------------------------------------------------------
-- PURPOSE
--   What customers spend money on: top product categories by revenue.
--
-- METRIC DEFINITION
--   "Category revenue" here = SUM(order_items.price), i.e. the product
--   value of goods sold, measured at the order_items grain. It is NOT
--   payment_value (which includes freight, discounts, split payments).
--   Both metrics coexist on the dashboard and are labelled differently.
--
-- GRAIN
--   order_items is grain (order_id, order_item_id). Joining it to
--   order_payments would DOUBLE COUNT, so these two analyses are kept
--   strictly separate. Categories with no translated name are grouped
--   under their Portuguese label via COALESCE.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TOP 5 CATEGORIES BY PRODUCT REVENUE
-- ---------------------------------------------------------------------
SELECT
  COALESCE(t.product_category_name_english, pr.product_category_name) AS category,
  COUNT(*)                       AS items_sold,
  COUNT(DISTINCT i.order_id)     AS orders,
  ROUND(SUM(i.price)::numeric, 2) AS revenue
FROM order_items i
JOIN products pr ON pr.product_id = i.product_id
LEFT JOIN product_category_name_translation t
       ON t.product_category_name = pr.product_category_name
GROUP BY category
ORDER BY revenue DESC
LIMIT 5;
-- Benchmarks (real data):
--   health_beauty         9,670 items |  8,836 orders | R$1,258,681.34
--   watches_gifts         5,991 items |  5,624 orders | R$1,205,005.68
--   bed_bath_table       11,115 items |  9,417 orders | R$1,036,988.68
--   sports_leisure        8,641 items |  7,720 orders | R$  988,048.97
--   computers_accessories 7,827 items |  6,689 orders | R$  911,954.32

-- ---------------------------------------------------------------------
-- 2. CATEGORY CONCENTRATION (single insight number)
--    The market is spread across many categories: the #1 category holds
--    under 10% of product revenue.
-- ---------------------------------------------------------------------
SELECT
  ROUND(100.0 *
        (SELECT MAX(cat_revenue)
         FROM (SELECT SUM(price) AS cat_revenue
               FROM order_items i JOIN products pr ON pr.product_id = i.product_id
               GROUP BY pr.product_category_name) cats) /
        (SELECT SUM(price) FROM order_items), 2) AS top_category_share_pct;
-- Benchmark: 9.26%

-- ---------------------------------------------------------------------
-- 3. CONTEXT -- AOV breakdown (product + freight) per order
-- ---------------------------------------------------------------------
SELECT
  ROUND(SUM(price)::numeric, 2)                    AS total_product_revenue,
  ROUND(SUM(freight_value)::numeric, 2)            AS total_freight,
  ROUND(SUM(price + freight_value)::numeric, 2)    AS total_order_value,
  COUNT(DISTINCT order_id)                         AS orders_with_items,
  ROUND((SUM(price + freight_value) / NULLIF(COUNT(DISTINCT order_id), 0))::numeric, 2)
                                                   AS avg_order_value_incl_freight
FROM order_items;
-- Benchmarks: R$13,591,643.70 | R$2,251,909.54 | R$15,843,553.24 |
--             98,666 orders | R$160.58
-- =====================================================================