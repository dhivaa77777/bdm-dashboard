-- =====================================================================
-- 10_dynamic_dashboard_indexes.sql
-- Performance indexes for dynamic dashboard queries
-- ---------------------------------------------------------------------
-- PURPOSE
--   Indexes to support the parameterized queries and dynamic views
--   introduced in 09_dynamic_dashboard.sql. Only creates indexes that
--   are justified by the query patterns in the upgraded dashboard.
--
--   Run AFTER 09_dynamic_dashboard.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- Orders table indexes for filtering and time-series queries
-- ---------------------------------------------------------------------
-- Date range filtering on order_purchase_timestamp
CREATE INDEX IF NOT EXISTS idx_orders_purchase_ts ON orders (order_purchase_timestamp);
-- Status filtering
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (order_status);
-- Customer lookup (already exists: idx_orders_customer_id)
-- Composite for date + status filtering
CREATE INDEX IF NOT EXISTS idx_orders_status_purchase_ts ON orders (order_status, order_purchase_timestamp);

-- ---------------------------------------------------------------------
-- Order Payments indexes for payment analysis and trend queries
-- ---------------------------------------------------------------------
-- Payment type filtering
CREATE INDEX IF NOT EXISTS idx_payments_type ON order_payments (payment_type);
-- Installments analysis
CREATE INDEX IF NOT EXISTS idx_payments_installments ON order_payments (payment_installments);
-- Order lookup (already exists: order_payments_pkey on (order_id, payment_sequential))
-- Composite for order-level aggregation after filtering
CREATE INDEX IF NOT EXISTS idx_payments_order_type ON order_payments (order_id, payment_type);

-- ---------------------------------------------------------------------
-- Order Items indexes for product/category analysis
-- ---------------------------------------------------------------------
-- Product lookup (already exists: idx_items_product)
-- Seller lookup (already exists: idx_items_seller)
-- Composite for category + order lookups
CREATE INDEX IF NOT EXISTS idx_items_product_order ON order_items (product_id, order_id);

-- ---------------------------------------------------------------------
-- Customers indexes for geographic and unique customer analysis
-- ---------------------------------------------------------------------
-- State filtering (already exists: idx_customers_state)
-- Unique customer analysis
CREATE INDEX IF NOT EXISTS idx_customers_unique_id ON customers (customer_unique_id);
-- Zip code for geolocation joins
CREATE INDEX IF NOT EXISTS idx_customers_zip_code ON customers (customer_zip_code_prefix);
-- Composite for state + unique_id aggregation
CREATE INDEX IF NOT EXISTS idx_customers_state_unique ON customers (customer_state, customer_unique_id);

-- ---------------------------------------------------------------------
-- Products indexes for category analysis
-- ---------------------------------------------------------------------
-- Category filtering (already exists: idx_products_category)
-- Category translation joins
CREATE INDEX IF NOT EXISTS idx_products_category_translation ON products (product_category_name);

-- ---------------------------------------------------------------------
-- Sellers indexes for seller analytics
-- ---------------------------------------------------------------------
-- State filtering
CREATE INDEX IF NOT EXISTS idx_sellers_state ON sellers (seller_state);
-- Seller ID is PK (already indexed)

-- ---------------------------------------------------------------------
-- Geolocation indexes for zip prefix enrichment
-- ---------------------------------------------------------------------
-- Zip prefix lookup (already exists: idx_geolocation_zip)

-- ---------------------------------------------------------------------
-- Order Reviews indexes for review analytics
-- ---------------------------------------------------------------------
-- Score filtering (already exists: idx_reviews_score)
-- Order lookup (already exists: idx_reviews_order)

-- ---------------------------------------------------------------------
-- Composite indexes for common multi-table join patterns
-- ---------------------------------------------------------------------
-- Payment trend: orders -> order_payments filtered by date
CREATE INDEX IF NOT EXISTS idx_orders_cust_purchase ON orders (customer_id, order_purchase_timestamp);
-- Category revenue: order_items -> products filtered by category
CREATE INDEX IF NOT EXISTS idx_items_prod_order ON order_items (product_id, order_id);
-- Seller revenue: order_items -> sellers
CREATE INDEX IF NOT EXISTS idx_items_seller_order ON order_items (seller_id, order_id);

-- =====================================================================
-- VERIFICATION
-- =====================================================================
SELECT indexname, tablename
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;