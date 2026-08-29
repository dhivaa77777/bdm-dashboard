# Database Schema

## Logical relationship map (authoritative reference)

This project follows the standard Olist relationship diagram. The dashboard's
"customer experience" path goes through `orders → reviews`; geography through
`customers/sellers → zip prefix → geolocation` (optional, not used on the main
dashboard).

```text
                 +---------------------------+
                 |    order_payments         |
                 |   order_id, payment_type, |
                 |   payment_value,          |
                 |   payment_installments    |
                 +-------------+-------------+
                               | order_id
                               v
+------------------+  +----------------------+   +------------------+
|  order_reviews   |  |        orders        |   |   order_items    |
|  review_id       |<-| order_id             |<->| order_id         |
|  order_id        |  | customer_id          |   | order_item_id    |
|  review_score    |  | order_status, dates  |   | product_id       |
+------------------+  +-----+----------+-----+   | seller_id, price |
                            |          |         | freight_value    |
                            |          +---------+---------+        |
                            | customer_id                       |    |
                            v                                   v    v
                    +--------------+                  +------------+  +-----------+
                    |  customers   |                  |  products  |  | sellers   |
                    | customer_id  |                  | product_id |  | seller_id |
                    | unique_id    |                  | category   |  | zip/state |
                    | state, city  |                  +-----+------+  +-----+-----+
                    +------+-------+                        |               |
                           |                                v               |
        zip_code_prefix -> +-----------------> geolocation <---------------+ zip_code_prefix
```

## Tables (created by `sql/01_database_setup.sql`)

| Table | Grain / PK | Key FKs |
|---|---|---|
| customers | customer_id (PK) | – |
| orders | order_id (PK) | customer_id → customers |
| order_items | (order_id, order_item_id) | product_id → products; seller_id → sellers |
| order_payments | (order_id, payment_sequential) | order_id → orders |
| order_reviews | grain: review row per order occurrence (review_id NOT unique in source) | order_id → orders |
| products | product_id (PK) | – |
| sellers | seller_id (PK) | – |
| geolocation | no PK (zip prefix) | – |
| product_category_name_translation | product_category_name (PK) | – |

## Dashboard-relevant join paths

| Analysis | Path |
|---|---|
| Payments | orders → payments (`order_id`) |
| Customers / states | customers → orders → payments |
| Product categories | orders → order_items → products → translation |
| Customer experience | orders → reviews |
| Geography (optional) | customers/sellers → zip prefix → geolocation |

## Cardinality rules that protect correctness

1. **orders 1──n payments** — many payment rows per order (split payments). Always
   aggregate `order_payments` at its own grain before joining elsewhere.
2. **customers 1──n orders (per customer_id)** — but for people use
   `customer_unique_id`; n customer_ids can map to 1 unique customer.
3. **orders 1──n order_items** — never join order_items to order_payments when
   summing money; it would multiply payment_value.
4. **orders 0..n reviews** — an order can carry several reviews.

## SQL object inventory

| Object | Purpose |
|---|---|
| 01_database_setup.sql | DDL: tables, PKs, FKs, indexes |
| 02_data_quality_checks.sql | validation queries + expected values |
| 03_kpi_queries.sql | headline KPIs |
| 04_payment_analysis.sql | payment type + installments |
| 05_customer_analysis.sql | top customers, states, concentration |
| 06_product_analysis.sql | top categories |
| 07_review_analysis.sql | customer experience |
| 08_dashboard_views.sql | `vw_*` views consumed by the dashboard |