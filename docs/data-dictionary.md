# Data Dictionary

Raw files live under `data/` locally (not committed). All money values are in
**Brazilian Real (R$)**. Durations: 2016-09 → 2018-10.

## customers (99,441 rows)
| Column | Type | Notes |
|---|---|---|
| customer_id | text (PK) | internal id, one per order row |
| customer_unique_id | text | a person; can span multiple customer_ids |
| customer_zip_code_prefix | text | join to geolocation |
| customer_city | text | lower-cased city |
| customer_state | text | 2-letter state (SP, RJ, MG, …) |

## orders (99,441 rows)
| Column | Type | Notes |
|---|---|---|
| order_id | text (PK) | |
| customer_id | text (FK → customers) | |
| order_status | text | delivered, shipped, canceled, … |
| order_purchase_timestamp | timestamptz | |
| order_approved_at | timestamptz | |
| order_delivered_carrier_date | timestamptz | |
| order_delivered_customer_date | timestamptz | |
| order_estimated_delivery_date | timestamptz | |

## order_items (112,650 rows) — grain (order_id, order_item_id)
| Column | Type | Notes |
|---|---|---|
| order_id | text (FK → orders) | |
| order_item_id | int | item position in the order |
| product_id | text (FK → products) | |
| seller_id | text (FK → sellers) | |
| shipping_limit_date | timestamptz | |
| price | numeric(10,2) | product value (revenue measure) |
| freight_value | numeric(10,2) | shipping charge |

## order_payments (103,886 rows) — grain (order_id, payment_sequential)
| Column | Type | Notes |
|---|---|---|
| order_id | text (FK → orders) | |
| payment_sequential | int | 1,2,3… within the order |
| payment_type | text | credit_card, boleto, voucher, debit_card, not_defined |
| payment_installments | int | number of installments |
| payment_value | numeric(10,2) | amount paid for this entry |

> An order can have several payment rows (split payments / multi-charges).
> `SUM(payment_value)` at this grain = **total payment value**.

| Metric (definition) | Formula | Validated value |
|---|---|---|
| Total payment value | `SUM(payment_value)` from order_payments | R$16,008,872.12 |
| Product revenue | `SUM(price)` from order_items | R$13,591,643.70 |
| Order value incl. freight | `SUM(price + freight_value)` | R$15,843,553.24 |

> These three totals deliberately differ; they are never mixed (see methodology).

## order_reviews (99,224 rows)
| Column | Type | Notes |
|---|---|---|
| review_id | text | **NOT unique in source** — 789 ids reused across different orders |
| order_id | text (FK → orders) | an order can have multiple reviews; the analytical join key |
| review_score | int (1–5) | |
| review_comment_title / message | text | often empty |
| review_creation_date / answer_timestamp | timestamptz | |

> Known Olist data quirk: a review id can be attached to **two different
> orders** (identical content/timing). Because of this, the row grain is
> "one review record per order occurrence" — `review_id` is deliberately
> *not* a primary key in this database.

## products (32,951 rows)
product_id (PK), product_category_name (pt), plus name/description lengths,
photo count, weight (g), length/height/width (cm).

## sellers (3,095 rows)
seller_id (PK), seller_zip_code_prefix, seller_city, seller_state.

## geolocation (~1,000,163 rows)
zip-code-prefix → lat/lng/city/state. Many rows per zip; **no PK**.
Used only for context (not on the dashboard).

## product_category_name_translation (71 rows)
Maps Portuguese category names to English.