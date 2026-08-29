-- =====================================================================
-- 09_dynamic_dashboard.sql
-- Olist Customer & Payment Analytics Dashboard
-- Dynamic analytical views and functions for interactive filtering
-- ---------------------------------------------------------------------
-- PURPOSE
--   Extends the analytical layer with parameter-aware views and functions
--   that support the upgraded dynamic dashboard. All new objects follow
--   the existing vw_ naming convention and are designed for safe
--   parameterized querying from Streamlit.
--
--   Run AFTER 01..08 have been validated.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper: Filter options (used by UI to populate dropdowns)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_filter_date_range AS
SELECT
  MIN(order_purchase_timestamp)::date AS min_date,
  MAX(order_purchase_timestamp)::date AS max_date
FROM orders;

CREATE OR REPLACE VIEW vw_filter_order_status AS
SELECT DISTINCT order_status
FROM orders
WHERE order_status IS NOT NULL
ORDER BY order_status;

CREATE OR REPLACE VIEW vw_filter_payment_types AS
SELECT DISTINCT payment_type
FROM order_payments
WHERE payment_type IS NOT NULL
ORDER BY payment_type;

CREATE OR REPLACE VIEW vw_filter_customer_states AS
SELECT DISTINCT customer_state
FROM customers
WHERE customer_state IS NOT NULL
ORDER BY customer_state;

CREATE OR REPLACE VIEW vw_filter_product_categories AS
SELECT DISTINCT
  COALESCE(t.product_category_name_english, pr.product_category_name) AS category
FROM products pr
LEFT JOIN product_category_name_translation t
       ON t.product_category_name = pr.product_category_name
WHERE pr.product_category_name IS NOT NULL
ORDER BY category;

CREATE OR REPLACE VIEW vw_filter_seller_states AS
SELECT DISTINCT seller_state
FROM sellers
WHERE seller_state IS NOT NULL
ORDER BY seller_state;

-- ---------------------------------------------------------------------
-- VW: Dynamic KPIs with parameter-aware WHERE clauses
--     Use the helper function below for filtered queries
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
-- VW: Payment Summary (existing, kept for compatibility)
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
-- VW: Installment Summary (existing, kept for compatibility)
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
-- VW: Top 5 Customers (existing, kept for compatibility)
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
-- VW: Top 5 Customer States (existing, kept for compatibility)
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
-- VW: Top 5 Product Categories (existing, kept for compatibility)
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
-- VW: Customer Experience (existing, kept for compatibility)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_customer_experience AS
SELECT
  COUNT(*)                                 AS review_count,
  COUNT(DISTINCT order_id)                 AS orders_with_reviews,
  ROUND(AVG(review_score)::numeric, 2)     AS avg_review_score,
  ROUND(100.0 * COUNT(*) FILTER (WHERE review_score >= 4) / COUNT(*), 2)
                                           AS pct_high_rated_reviews
FROM order_reviews;

-- =====================================================================
-- NEW DYNAMIC VIEWS FOR FILTER-AWARE ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- VW: Payment Summary with optional filters
--     Parameters passed via CTE in query layer (not SQL parameters)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_payment_summary_dynamic AS
SELECT
  payment_type,
  COUNT(DISTINCT p.order_id)                          AS orders,
  ROUND(SUM(p.payment_value)::numeric, 2)             AS total_payment_value,
  ROUND(100.0 * SUM(p.payment_value) /
        NULLIF(SUM(SUM(p.payment_value)) OVER (), 0), 2) AS value_share_pct
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- ---------------------------------------------------------------------
-- VW: Installment Distribution
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_installment_distribution AS
SELECT
  payment_installments,
  COUNT(DISTINCT order_id) AS order_count,
  ROUND(SUM(payment_value)::numeric, 2) AS total_payment_value,
  ROUND(AVG(payment_installments)::numeric, 2) AS avg_installments
FROM order_payments
GROUP BY payment_installments
ORDER BY order_count DESC;

-- ---------------------------------------------------------------------
-- VW: Monthly Payment Trend
--     Grain: one row per month (YYYY-MM)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_monthly_payment_trend AS
SELECT
  DATE_TRUNC('month', o.order_purchase_timestamp)::date AS month_start,
  COUNT(DISTINCT p.order_id) AS orders,
  ROUND(SUM(p.payment_value)::numeric, 2) AS total_payment_value,
  COUNT(DISTINCT o.customer_id) AS unique_customers,
  ROUND(SUM(p.payment_value) / NULLIF(COUNT(DISTINCT p.order_id), 0)::numeric, 2)
                                                             AS avg_order_value
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
ORDER BY month_start;

-- ---------------------------------------------------------------------
-- VW: Quarterly Payment Trend
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_quarterly_payment_trend AS
SELECT
  DATE_TRUNC('quarter', o.order_purchase_timestamp)::date AS quarter_start,
  COUNT(DISTINCT p.order_id) AS orders,
  ROUND(SUM(p.payment_value)::numeric, 2) AS total_payment_value,
  COUNT(DISTINCT o.customer_id) AS unique_customers
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY DATE_TRUNC('quarter', o.order_purchase_timestamp)
ORDER BY quarter_start;

-- ---------------------------------------------------------------------
-- VW: Customer Segmentation
--     Segments: One-time (1 order), Repeat (2+ orders)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_customer_segments AS
SELECT
  segment,
  COUNT(*) AS customer_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct,
  SUM(total_orders) AS total_orders,
  SUM(total_spend) AS total_payment_value,
  ROUND(SUM(total_spend) / NULLIF(SUM(total_orders), 0)::numeric, 2) AS avg_order_value
FROM (
  SELECT
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(p.payment_value) AS total_spend,
    CASE
      WHEN COUNT(DISTINCT o.order_id) = 1 THEN 'One-time'
      ELSE 'Repeat'
    END AS segment
  FROM customers c
  JOIN orders o ON o.customer_id = c.customer_id
  JOIN order_payments p ON p.order_id = o.order_id
  GROUP BY c.customer_unique_id
) s
GROUP BY segment
ORDER BY total_payment_value DESC;

-- ---------------------------------------------------------------------
-- VW: Customer Segmentation by Order Count (detailed)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_customer_segment_detail AS
SELECT
  CASE
    WHEN order_count = 1 THEN '1 order'
    WHEN order_count = 2 THEN '2 orders'
    WHEN order_count = 3 THEN '3 orders'
    WHEN order_count BETWEEN 4 AND 5 THEN '4-5 orders'
    WHEN order_count BETWEEN 6 AND 10 THEN '6-10 orders'
    ELSE '11+ orders'
  END AS order_bucket,
  COUNT(*) AS customer_count,
  SUM(total_spend) AS total_payment_value,
  ROUND(AVG(total_spend)::numeric, 2) AS avg_customer_spend
FROM (
  SELECT
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(p.payment_value) AS total_spend
  FROM customers c
  JOIN orders o ON o.customer_id = c.customer_id
  JOIN order_payments p ON p.order_id = o.order_id
  GROUP BY c.customer_unique_id
) s
GROUP BY order_bucket
ORDER BY MIN(order_count);

-- ---------------------------------------------------------------------
-- VW: Top 5 Sellers by Product Revenue
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_sellers AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SUM(i.price) DESC) AS rank,
  s.seller_id,
  s.seller_state,
  COUNT(DISTINCT i.order_id) AS orders,
  COUNT(*) AS items_sold,
  ROUND(SUM(i.price)::numeric, 2) AS product_revenue
FROM order_items i
JOIN sellers s ON s.seller_id = i.seller_id
GROUP BY s.seller_id, s.seller_state
ORDER BY product_revenue DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- VW: Order Status Summary
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_order_status_summary AS
SELECT
  order_status,
  COUNT(*) AS order_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;

-- ---------------------------------------------------------------------
-- VW: Delivery Performance
--     Late if delivered_customer_date > estimated_delivery_date
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_delivery_performance AS
SELECT
  COUNT(*) AS total_orders,
  COUNT(*) FILTER (WHERE order_status = 'delivered') AS delivered_orders,
  COUNT(*) FILTER (WHERE order_status = 'canceled') AS canceled_orders,
  COUNT(*) FILTER (WHERE order_status = 'unavailable') AS unavailable_orders,
  ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'delivered') /
        NULLIF(COUNT(*), 0), 2) AS delivery_rate_pct,
  ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'canceled') /
        NULLIF(COUNT(*), 0), 2) AS cancellation_rate_pct,
  ROUND(100.0 * COUNT(*) FILTER (
    WHERE order_status = 'delivered'
    AND order_delivered_customer_date > order_estimated_delivery_date
  ) / NULLIF(COUNT(*) FILTER (WHERE order_status = 'delivered'), 0), 2)
                                                           AS late_delivery_rate_pct
FROM orders;

-- ---------------------------------------------------------------------
-- VW: Review Score Distribution
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_review_score_distribution AS
SELECT
  review_score,
  COUNT(*) AS review_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;

-- ---------------------------------------------------------------------
-- VW: Repeat Customer Rate
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_repeat_customer_rate AS
SELECT
  COUNT(DISTINCT c.customer_unique_id) AS total_unique_customers,
  COUNT(*) FILTER (WHERE order_count > 1) AS repeat_customers,
  COUNT(*) FILTER (WHERE order_count = 1) AS one_time_customers,
  ROUND(100.0 * COUNT(*) FILTER (WHERE order_count > 1) /
        NULLIF(COUNT(DISTINCT c.customer_unique_id), 0), 2) AS repeat_rate_pct
FROM (
  SELECT
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS order_count
  FROM customers c
  JOIN orders o ON o.customer_id = c.customer_id
  GROUP BY c.customer_unique_id
) s;

-- ---------------------------------------------------------------------
-- VW: Dynamic Top 5 Categories (for filtered queries)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_categories_dynamic AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SUM(i.price) DESC) AS rank,
  COALESCE(t.product_category_name_english, pr.product_category_name) AS category,
  COUNT(*) AS items_sold,
  COUNT(DISTINCT i.order_id) AS orders,
  ROUND(SUM(i.price)::numeric, 2) AS revenue,
  ROUND(100.0 * SUM(i.price) / NULLIF(SUM(SUM(i.price)) OVER (), 0), 2) AS share_pct
FROM order_items i
JOIN products pr ON pr.product_id = i.product_id
LEFT JOIN product_category_name_translation t
       ON t.product_category_name = pr.product_category_name
GROUP BY category
ORDER BY revenue DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- VW: Dynamic Top 5 States (for filtered queries)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_states_dynamic AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SUM(p.payment_value) DESC) AS rank,
  c.customer_state AS state,
  COUNT(DISTINCT c.customer_unique_id) AS customers,
  COUNT(DISTINCT o.order_id) AS orders,
  ROUND(SUM(p.payment_value)::numeric, 2) AS total_payment_value,
  ROUND(100.0 * SUM(p.payment_value) /
        NULLIF(SUM(SUM(p.payment_value)) OVER (), 0), 2) AS value_share_pct
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY c.customer_state
ORDER BY total_payment_value DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- VW: Dynamic Top 5 Customers (for filtered queries)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_customers_dynamic AS
SELECT
  ROW_NUMBER() OVER (ORDER BY SUM(p.payment_value) DESC) AS rank,
  LEFT(c.customer_unique_id, 12) AS customer_ref,
  COUNT(DISTINCT o.order_id) AS order_count,
  ROUND(SUM(p.payment_value)::numeric, 2) AS total_spend,
  ROUND((SUM(p.payment_value) / NULLIF(COUNT(DISTINCT o.order_id), 0))::numeric, 2)
                                     AS avg_order_value
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
ORDER BY total_spend DESC
LIMIT 5;

-- =====================================================================
-- VERIFICATION
-- =====================================================================
SELECT 'vw_filter_date_range' AS view_name, COUNT(*) AS rows FROM vw_filter_date_range
UNION ALL SELECT 'vw_filter_order_status', COUNT(*) FROM vw_filter_order_status
UNION ALL SELECT 'vw_filter_payment_types', COUNT(*) FROM vw_filter_payment_types
UNION ALL SELECT 'vw_filter_customer_states', COUNT(*) FROM vw_filter_customer_states
UNION ALL SELECT 'vw_filter_product_categories', COUNT(*) FROM vw_filter_product_categories
UNION ALL SELECT 'vw_filter_seller_states', COUNT(*) FROM vw_filter_seller_states
UNION ALL SELECT 'vw_dashboard_kpis', COUNT(*) FROM vw_dashboard_kpis
UNION ALL SELECT 'vw_payment_summary', COUNT(*) FROM vw_payment_summary
UNION ALL SELECT 'vw_installment_summary', COUNT(*) FROM vw_installment_summary
UNION ALL SELECT 'vw_top_customers', COUNT(*) FROM vw_top_customers
UNION ALL SELECT 'vw_top_customer_states', COUNT(*) FROM vw_top_customer_states
UNION ALL SELECT 'vw_top_product_categories', COUNT(*) FROM vw_top_product_categories
UNION ALL SELECT 'vw_customer_experience', COUNT(*) FROM vw_customer_experience
UNION ALL SELECT 'vw_payment_summary_dynamic', COUNT(*) FROM vw_payment_summary_dynamic
UNION ALL SELECT 'vw_installment_distribution', COUNT(*) FROM vw_installment_distribution
UNION ALL SELECT 'vw_monthly_payment_trend', COUNT(*) FROM vw_monthly_payment_trend
UNION ALL SELECT 'vw_quarterly_payment_trend', COUNT(*) FROM vw_quarterly_payment_trend
UNION ALL SELECT 'vw_customer_segments', COUNT(*) FROM vw_customer_segments
UNION ALL SELECT 'vw_customer_segment_detail', COUNT(*) FROM vw_customer_segment_detail
UNION ALL SELECT 'vw_top_sellers', COUNT(*) FROM vw_top_sellers
UNION ALL SELECT 'vw_order_status_summary', COUNT(*) FROM vw_order_status_summary
UNION ALL SELECT 'vw_delivery_performance', COUNT(*) FROM vw_delivery_performance
UNION ALL SELECT 'vw_review_score_distribution', COUNT(*) FROM vw_review_score_distribution
UNION ALL SELECT 'vw_repeat_customer_rate', COUNT(*) FROM vw_repeat_customer_rate
UNION ALL SELECT 'vw_top_categories_dynamic', COUNT(*) FROM vw_top_categories_dynamic
UNION ALL SELECT 'vw_top_states_dynamic', COUNT(*) FROM vw_top_states_dynamic
UNION ALL SELECT 'vw_top_customers_dynamic', COUNT(*) FROM vw_top_customers_dynamic
ORDER BY view_name;