-- =====================================================================
-- 07_review_analysis.sql
-- Olist Customer & Payment Analytics Dashboard
-- ---------------------------------------------------------------------
-- PURPOSE
--   Customer experience: a compact satisfaction view (dashboard gets only
--   a small card - the analysis exists here, not on the dashboard).
--
-- NOTE
--   An order can receive several reviews. Two interpretations exist:
--     1) per review   -> AVG(review_score) over order_reviews
--     2) per order    -> take the best (or first) review per order
--   The dataset yields the SAME average (4.09) for both; we display the
--   per-review average and document the choice in docs/methodology.md.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. HEADLINE SATISFACTION METRICS
-- ---------------------------------------------------------------------
SELECT
  COUNT(*)                                    AS review_count,           -- 99,224
  COUNT(DISTINCT order_id)                    AS orders_with_reviews,    -- 98,673
  ROUND(AVG(review_score)::numeric, 2)        AS avg_review_score,       -- 4.09
  ROUND(100.0 * COUNT(*) FILTER (WHERE review_score >= 4) / COUNT(*), 2)
                                              AS pct_high_rated_reviews, -- 77.07
  ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2)
                                              AS pct_low_rated_reviews
FROM order_reviews;

-- ---------------------------------------------------------------------
-- 2. SCORE DISTRIBUTION (context, not on the dashboard)
-- ---------------------------------------------------------------------
SELECT
  review_score,
  COUNT(*) AS reviews,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;
-- 5* dominates; distribution is heavily right-skewed.

-- ---------------------------------------------------------------------
-- 3. PER-ORDER INTERPRETATION (sanity check of the two methods)
-- ---------------------------------------------------------------------
SELECT
  ROUND(AVG(s)::numeric, 2) AS avg_per_order
FROM (
  SELECT order_id, MAX(review_score) AS s
  FROM order_reviews
  GROUP BY order_id
) sub;
-- Benchmark: 4.09 (matches the per-review average)
-- =====================================================================