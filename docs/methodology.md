# Methodology

Every dashboard number is reproduced by SQL from Supabase at run time. The
values below are **validation benchmarks** measured on the real dataset — never
hard-coded into SQL or the app. If a live query disagrees, investigate rather
than forcing it.

## 1. Metric definitions

| Metric | Definition | Formula | Benchmark |
|---|---|---|---|
| Total payment value | money actually paid | `SUM(payment_value)` on order_payments | R$16,008,872.12 |
| Paid orders | orders having ≥1 payment row | `COUNT(DISTINCT order_id)` on order_payments | 99,440 |
| Total orders | all orders | `COUNT(DISTINCT order_id)` on orders | 99,441 |
| Delivered orders | subset of orders | `… WHERE order_status='delivered'` | 96,478 |
| Unique customers | distinct people | `COUNT(DISTINCT customer_unique_id)` | 96,096 |
| Average order value | value per paid order | total payment value ÷ paid orders | R$160.99 |
| Avg review score | satisfaction | `AVG(review_score)` on order_reviews | 4.09 |
| % high-rated | share ≥4/5 | `COUNT(*) FILTER (score>=4) / COUNT(*)` | 77.07% |

> **Do not mix money metrics.** `payment_value` (R$16.0M) ≠ `price`
> (R$13.59M) ≠ `price + freight` (R$15.84M). The dashboard labels each one.

## 2. Payment analysis

- **Payment types:** pivot `payment_type` → distinct orders, `SUM(payment_value)`,
  share-of-value via window function; `ORDER BY` value DESC.
  Benchmarks: credit_card 78.34%, boleto 17.92%, voucher 2.37%, debit_card
  1.36%; 3 rows of type `not_defined` (value 0) exist and are excluded from the
  visual.
- **Installments:** distinct orders per `payment_installments`, ranked by order
  count. **51.5%** of paid orders use >1 installment (51,170 / 99,440). The
  common "≈49%" figure is the **payment-row** level (49.4% of rows), which
  differs because of split payments — this project reports the order level.

## 3. Customer analysis

- **Identity:** aggregate by `customer_unique_id` (96,096 people) — using
  `customer_id` would misrepresent unique customers (99,441 ids).
- **Top 5 customers:** rank by `SUM(payment_value)` DESC, show order count +
  AOV. Top customer ≈ R$13.7K.
- **Concentration:** Top-5 customers = **0.28%** of value → highly distributed
  B2C base; Top-5 states = **73.19%** → geography is where value concentrates.
- **States:** `customer_state` from customers via orders, ranked by payment value.

## 4. Product analysis

- **Category revenue:** `SUM(order_items.price)` joined to products and the
  PT→EN translation; ranked DESC, Top 5. Never mixed with payment value.
- Benchmark top category: health_beauty ≈ R$1.26M (9.3% of product revenue).

## 5. Customer experience

- Read `review_score` only; dashboard shows a one-line card (avg + % ≥4).
- Two interpretations (per review vs per order) both average 4.09; the
  per-review average is reported and this choice is documented.

## 6. Validation discipline

1. Run `02_data_quality_checks.sql` against the loaded DB and compare to the
   expected row counts.
2. Cross-check `03_kpi_queries.sql` totals against the raw tables.
3. Confirm Top-5 lists and percentages match the benchmarks above.
4. Only then does the Streamlit app read the `vw_*` views (08).

## 7. Traceability

| Dashboard element | View | Source tables | Calculation |
|---|---|---|---|
| Total payment value | vw_dashboard_kpis | order_payments | SUM(payment_value) |
| Orders / paid orders | vw_dashboard_kpis | orders, order_payments | COUNT(DISTINCT …) |
| Unique customers | vw_dashboard_kpis | customers | COUNT DISTINCT unique_id |
| Avg order value | vw_dashboard_kpis | order_payments | total ÷ paid orders |
| Avg rating / % high-rated | vw_dashboard_kpis, vw_customer_experience | order_reviews | AVG(score), % ≥4 |
| Installment usage | vw_dashboard_kpis, vw_installment_summary | order_payments | COUNT DISTINCT >1 inst |
| Payment methods | vw_payment_summary | order_payments | GROUP BY payment_type |
| Top customers | vw_top_customers | customers/orders/payments | ORDER BY spend DESC LIMIT 5 |
| Top states | vw_top_customer_states | customers/orders/payments | GROUP BY state |
| Top categories | vw_top_product_categories | items/products/translation | GROUP BY category |