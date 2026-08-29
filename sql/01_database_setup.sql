-- =====================================================================
-- 01_database_setup.sql
-- Olist Customer & Payment Analytics Dashboard
-- ---------------------------------------------------------------------
-- PURPOSE
--   Creates the Supabase (PostgreSQL) schema that stores the raw Olist
--   dataset and preserves its original relationships.
--
-- HOW TO USE
--   1. Open Supabase Dashboard -> SQL Editor (or psql / psycopg).
--   2. Run this file FIRST, then load the data (see "LOADING THE DATA").
--   3. Run 02_data_quality_checks.sql to validate the load.
--   4. Run 03..07 (analytical SQL) and finally 08_dashboard_views.sql.
--
-- NOTE ON LOADING
--   The original Olist CSVs ship with a UTF-8 BOM on the first column of
--   each file.  When importing via the Supabase dashboard CSV importer,
--   strip the BOM (or load with COPY and CSV HEADER, then clean the first
--   column name if needed).  Column names below are the CLEAN names.
-- =====================================================================

-- ---------------------------------------------------------------------
-- DROP EXISTING OBJECTS (idempotent-ish setup; safe to re-run at start)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS vw_dashboard_kpis;
DROP VIEW IF EXISTS vw_payment_summary;
DROP VIEW IF EXISTS vw_installment_summary;
DROP VIEW IF EXISTS vw_top_customers;
DROP VIEW IF EXISTS vw_top_customer_states;
DROP VIEW IF EXISTS vw_top_product_categories;
DROP VIEW IF EXISTS vw_customer_experience;

DROP TABLE IF EXISTS order_reviews;
DROP TABLE IF EXISTS order_payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS geolocation;
DROP TABLE IF EXISTS product_category_name_translation;

-- ---------------------------------------------------------------------
-- 1. CUSTOMERS
--    One customer_id per order; a single person may hold several
--    customer_ids -> analyse people via customer_unique_id.
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id              text PRIMARY KEY,
    customer_unique_id       text NOT NULL,
    customer_zip_code_prefix text,
    customer_city            text,
    customer_state           text
);

CREATE INDEX idx_customers_unique_id      ON customers (customer_unique_id);
CREATE INDEX idx_customers_zip_code       ON customers (customer_zip_code_prefix);
CREATE INDEX idx_customers_state          ON customers (customer_state);

-- ---------------------------------------------------------------------
-- 2. ORDERS
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id                      text PRIMARY KEY,
    customer_id                   text NOT NULL REFERENCES customers (customer_id),
    order_status                  text,
    order_purchase_timestamp      timestamptz,
    order_approved_at             timestamptz,
    order_delivered_carrier_date  timestamptz,
    order_delivered_customer_date timestamptz,
    order_estimated_delivery_date timestamptz
);

CREATE INDEX idx_orders_customer_id  ON orders (customer_id);
CREATE INDEX idx_orders_status       ON orders (order_status);
CREATE INDEX idx_orders_purchase_ts  ON orders (order_purchase_timestamp);

-- ---------------------------------------------------------------------
-- 3. PRODUCTS
-- ---------------------------------------------------------------------
CREATE TABLE products (
    product_id                  text PRIMARY KEY,
    product_category_name       text,
    product_name_lenght         integer,
    product_description_lenght  integer,
    product_photos_qty          integer,
    product_weight_g            integer,
    product_length_cm           integer,
    product_height_cm           integer,
    product_width_cm            integer
);

CREATE INDEX idx_products_category ON products (product_category_name);

-- ---------------------------------------------------------------------
-- 4. SELLERS
-- ---------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id              text PRIMARY KEY,
    seller_zip_code_prefix text,
    seller_city            text,
    seller_state           text
);

-- ---------------------------------------------------------------------
-- 5. ORDER_ITEMS
--    GRAIN: one row per (order_id, order_item_id).
--    price = product revenue, freight_value = shipping.  SUM(price) is
--    NOT the same as SUM(payment_value).
-- ---------------------------------------------------------------------
CREATE TABLE order_items (
    order_id            text NOT NULL REFERENCES orders (order_id),
    order_item_id       integer NOT NULL,
    product_id          text REFERENCES products (product_id),
    seller_id           text REFERENCES sellers (seller_id),
    shipping_limit_date timestamptz,
    price               numeric(10,2),
    freight_value       numeric(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE INDEX idx_items_product ON order_items (product_id);
CREATE INDEX idx_items_seller  ON order_items (seller_id);

-- ---------------------------------------------------------------------
-- 6. ORDER_PAYMENTS
--    GRAIN: one row per (order_id, payment_sequential).
--    An order may have MORE THAN ONE payment row (split payments and/or
--    multiple sequential charges).  ALWAYS SUM(payment_value) at this
--    grain and never join payments to another 1-to-many table without
--    pre-aggregating -- otherwise values are double counted.
-- ---------------------------------------------------------------------
CREATE TABLE order_payments (
    order_id             text NOT NULL REFERENCES orders (order_id),
    payment_sequential   integer NOT NULL,
    payment_type         text,
    payment_installments integer,
    payment_value        numeric(10,2),
    PRIMARY KEY (order_id, payment_sequential)
);

CREATE INDEX idx_payments_type         ON order_payments (payment_type);
CREATE INDEX idx_payments_installments ON order_payments (payment_installments);

-- ---------------------------------------------------------------------
-- 7. ORDER_REVIEWS
--    IMPORTANT (real-dataset finding): review_id is NOT unique in the
--    source. 789 review_id values are reused across DIFFERENT orders
--    (same review content/timestamps attached to two orders). Therefore
--    review_id is NOT a primary key here; the row grain is one review
--    record per order occurrence. order_id is the analytical join key.
-- ---------------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id               text NOT NULL,
    order_id                text REFERENCES orders (order_id),
    review_score            integer,
    review_comment_title    text,
    review_comment_message  text,
    review_creation_date    timestamptz,
    review_answer_timestamp timestamptz
);

CREATE INDEX idx_reviews_id    ON order_reviews (review_id);
CREATE INDEX idx_reviews_order ON order_reviews (order_id);
CREATE INDEX idx_reviews_score ON order_reviews (review_score);

-- ---------------------------------------------------------------------
-- 8. GEOGRAPHY (zip prefixes)
--    No natural PK: many rows share one zip_code_prefix.
-- ---------------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_zip_code_prefix text,
    geolocation_lat             double precision,
    geolocation_lng             double precision,
    geolocation_city            text,
    geolocation_state           text
);

CREATE INDEX idx_geolocation_zip ON geolocation (geolocation_zip_code_prefix);

-- ---------------------------------------------------------------------
-- 9. CATEGORY TRANSLATION (pt -> en)
-- ---------------------------------------------------------------------
CREATE TABLE product_category_name_translation (
    product_category_name          text PRIMARY KEY,
    product_category_name_english  text
);

-- ---------------------------------------------------------------------
-- LOADING THE DATA
-- ---------------------------------------------------------------------
-- The raw CSVs (data/olist_*.csv) are NOT committed to git. Place the
-- original files under data/ locally, then load them in one of two ways:
--
--  A) Supabase Dashboard -> Table Editor -> "Import data from CSV"
--     for each table above (remember to strip the UTF-8 BOM from the
--     first column name if present).
--
--  B) From this machine with the supplied loader (psycopg2 COPY):
--       pip install -r dashboard/requirements.txt
--       python dashboard/load_data.py --csv-dir data
--     (set SUPABASE_DATABASE_URL in .env first).  COPY is faster and
--     more repeatable than the dashboard importer.
--
-- Useful verification after the load (expected row counts from the real
-- dataset -- the load must match them exactly):
--   customers                        99,441
--   orders                           99,441   (96,478 delivered)
--   order_payments                  103,886   (99,440 distinct orders)
--   order_items                     112,650
--   products                         32,951
--   order_reviews                    99,224
--   sellers                           3,095
--   geolocation                   ~1,000,163
--   product_category_name_translation    71
-- =====================================================================