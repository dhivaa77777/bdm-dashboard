-- =====================================================================
-- 08_dashboard_views.sql
-- Olist Customer & Payment Analytics Dashboard
-- ---------------------------------------------------------------------
-- PURPOSE
--   Materializes every analytical query as a database VIEW consumed by
--   the dashboard. The Streamlit app reads ONLY these views, never raw
--   tables or ad-hoc joins.
--
--   RAW TABLES -> DATA QUALITY -> ANALYTICAL SQL -> vw_* VIEWS -> DASHBOARD
--
--   Run this file AFTER 01..07 have been validated. Views are created
--   with CREATE OR REPLACE so they can be refreshed safely.
-- =====================================================================

-- ---------------------------------------------------------------------
-- VW 1: HEADLINE KPIs + the insight numbers that feed the text bullets.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_dashboard_kpis AS
SELECT
  pay.total_payment_value,
  pay.total_paid_orders,
  ord.total_orders,
  ord.delivered_orders,
  cus.unique_customers,
  ROUND(pay.total_payment_value / NULLIF(pay.total_paid_orders, 0)::numeric, 2)
                                                          AS average_order_value,
  rev.avg_review_score,
  rev.pct_high_rated_reviews,
  inst.installment_order_pct,
  conc_cust.top5_customer_share_pct,
  conc_state.top5_state_share_pct,
  conc_cat.top_category_share_pct
FROM (
  SELECT ROUND(SUM(payment_value)::numeric, 2) AS total_payment_value,
         COUNT(DISTINCT order_id)             AS total_paid_orders
  FROM order_payments
) pay
CROSS JOIN (
  SELECT COUNT(DISTINCT order_id)                          AS total_orders,
         COUNT(DISTINCT order_id) FILTER (WHERE order_status = 'delivered')
                                                            AS delivered_orders
  FROM orders
) ord
CROSS JOIN (
  SELECT COUNT(DISTINCT customer_unique_id) AS unique_customers
  FROM customers
) cus
CROSS JOIN (
  SELECT ROUND(AVG(review_score)::numeric, 2) AS avg_review_score,
         ROUND(100.0 * COUNT(*) FILTER (WHERE review_score >= 4) / COUNT(*), 2)
                                            AS pct_high_rated_reviews
  FROM order_reviews
) rev
CROSS JOIN (
  SELECT ROUND(100.0 * COUNT(DISTINCT order_id) FILTER (WHERE payment_installments > 1)
              / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS installment_order_pct
  FROM order_payments
) inst
CROSS JOIN (
  SELECT ROUND(100.0 * SUM(total_spend) /
    NULLIF((SELECT SUM(payment_value) FROM order_payments), 0), 2) AS top5_customer_share_pct
  FROM (
    SELECT SUM(p.payment_value) AS total_spend
    FROM order_payments p
    JOIN orders o    ON o.order_id = p.order_id
    JOIN customers c ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
    ORDER BY total_spend DESC
    LIMIT 5
  ) t
) conc_cust
CROSS JOIN (
  SELECT ROUND(100.0 * SUM(total_payment_value) /
    NULLIF((SELECT SUM(payment_value) FROM order_payments), 0), 2) AS top5_state_share_pct
  FROM (
    SELECT SUM(p.payment_value) AS total_payment_value
    FROM order_payments p
    JOIN orders o    ON o.order_id = p.order_id
    JOIN customers c ON c.customer_id = o.customer_id
    GROUP BY c.customer_state
    ORDER BY total_payment_value DESC
    LIMIT 5
  ) t
) conc_state
CROSS JOIN (
  SELECT ROUND(100.0 * MAX(cat_revenue) /
    NULLIF((SELECT SUM(price) FROM order_items), 0), 2) AS top_category_share_pct
  FROM (
    SELECT SUM(i.price) AS cat_revenue
    FROM order_items i
    JOIN products pr ON pr.product_id = i.product_id
    GROUP BY pr.product_category_name
  ) c
) conc_cat;

-- ---------------------------------------------------------------------
-- VW 2: PAYMENT TYPE SUMMARY
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_payment_summary AS
SELECT
  payment_type,
  COUNT(DISTINCT order_id)                          AS orders,
  ROUND(SUM(payment_value)::numeric, 2)             AS total_payment_value,
  ROUND(100.0 * SUM(payment_value) / NULLIF(SUM(SUM(payment_value)) OVER (), 0), 2)
                                                    AS value_share_pct
FROM order_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- ---------------------------------------------------------------------
-- VW 3: INSTALLMENT SUMMARY (top patterns)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_installment_summary AS
SELECT
  payment_installments,
  COUNT(DISTINCT order_id) AS order_count,
  ROUND(SUM(payment_value)::numeric, 2) AS total_payment_value
FROM order_payments
GROUP BY payment_installments
ORDER BY order_count DESC
LIMIT 6;

-- ---------------------------------------------------------------------
-- VW 4: TOP 5 CUSTOMERS BY SPEND
--    Customer id kept as a masked prefix for display only; aggregate by
--    customer_unique_id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_customers AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SUM(p.payment_value) DESC) AS rank,
  LEFT(c.customer_unique_id, 12) AS customer_ref,
  COUNT(DISTINCT o.order_id)     AS order_count,
  ROUND(SUM(p.payment_value)::numeric, 2) AS total_spend,
  ROUND((SUM(p.payment_value) / NULLIF(COUNT(DISTINCT o.order_id), 0))::numeric, 2)
                                 AS avg_order_value
FROM order_payments p
JOIN orders o    ON o.order_id = p.order_id
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
ORDER BY total_spend DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- VW 5: TOP 5 CUSTOMER STATES BY PAYMENT VALUE
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_customer_states AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SUM(p.payment_value) DESC) AS rank,
  c.customer_state AS state,
  COUNT(DISTINCT c.customer_unique_id) AS customers,
  COUNT(DISTINCT o.order_id)           AS orders,
  ROUND(SUM(p.payment_value)::numeric, 2) AS total_payment_value,
  ROUND(100.0 * SUM(p.payment_value) /
        NULLIF(SUM(SUM(p.payment_value)) OVER (), 0), 2) AS value_share_pct
FROM order_payments p
JOIN orders o    ON o.order_id = p.order_id
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY c.customer_state
ORDER BY total_payment_value DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- VW 6: TOP 5 PRODUCT CATEGORIES BY REVENUE
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_product_categories AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SUM(i.price) DESC) AS rank,
  COALESCE(t.product_category_name_english, pr.product_category_name) AS category,
  COUNT(*)                        AS items_sold,
  COUNT(DISTINCT i.order_id)      AS orders,
  ROUND(SUM(i.price)::numeric, 2) AS revenue
FROM order_items i
JOIN products pr ON pr.product_id = i.product_id
LEFT JOIN product_category_name_translation t
       ON t.product_category_name = pr.product_category_name
GROUP BY category
ORDER BY revenue DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- VW 7: CUSTOMER EXPERIENCE (small card)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_customer_experience AS
SELECT
  COUNT(*)                                 AS review_count,
  COUNT(DISTINCT order_id)                 AS orders_with_reviews,
  ROUND(AVG(review_score)::numeric, 2)     AS avg_review_score,
  ROUND(100.0 * COUNT(*) FILTER (WHERE review_score >= 4) / COUNT(*), 2)
                                           AS pct_high_rated_reviews
FROM order_reviews;

-- ---------------------------------------------------------------------
-- VERIFY: every view should return exactly 1 row except the
-- summary/top views (payment summary = 5, installment = 6, top* = 5).
-- ---------------------------------------------------------------------
SELECT 'vw_dashboard_kpis' AS view_name, COUNT(*) AS rows FROM vw_dashboard_kpis
UNION ALL SELECT 'vw_payment_summary', COUNT(*) FROM vw_payment_summary
UNION ALL SELECT 'vw_installment_summary', COUNT(*) FROM vw_installment_summary
UNION ALL SELECT 'vw_top_customers', COUNT(*) FROM vw_top_customers
UNION ALL SELECT 'vw_top_customer_states', COUNT(*) FROM vw_top_customer_states
UNION ALL SELECT 'vw_top_product_categories', COUNT(*) FROM vw_top_product_categories
UNION ALL SELECT 'vw_customer_experience', COUNT(*) FROM vw_customer_experience
ORDER BY view_name;
-- =====================================================================