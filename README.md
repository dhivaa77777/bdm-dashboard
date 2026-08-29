# Olist Customer & Payment Analytics Dashboard

A compact, management-style analytics project for the **Olist** (Brazilian
e-commerce marketplace) dataset. It answers, from a customer's point of view:
*how much are we earning, how do customers pay, who are the top customers and
states, what do they buy, and are they satisfied?*

The dashboard is deliberately **small and highly aggregated** — a viewer must
extract the business story in **≤ 20 seconds**. The heavy lifting lives in
reproducible SQL on **Supabase (PostgreSQL)**, and everything is documented on
GitHub.

---

## 1. Project overview

| | |
|---|---|
| Source data | Public Olist dataset, ~Sep 2016 – Oct 2018, 99,441 orders, 96,096 unique customers |
| Currency | Brazilian Real (R$) |
| Database | Supabase PostgreSQL (source of truth) |
| Analysis | SQL (data-quality → KPIs → payment/customer/product/review → views) |
| Presentation | Streamlit dashboard reading only `vw_*` views |
| Repository | This GitHub repo: code, SQL, docs, screenshots |

## 2. Business problem & objectives

Management wants to understand the business in under 20 seconds: payments,
top customers, customer behaviour, geography, and satisfaction. The project
therefore produces **aggregated, ranked, Top-5-style** views — no bulky
visualisations, no raw transaction dump.

## 3. Key questions answered

1. How much was paid, how many orders, and how many unique customers?
2. How do customers pay (payment-type mix)?
3. How do customers use installments?
4. Who are the Top 5 customers and how concentrated is the customer base?
5. Which Top 5 states generate payments?
6. Which Top 5 product categories generate revenue?
7. How satisfied are customers (review score)?

## 4. Architecture

```text
Raw Olist CSVs (data/, local only)
        ↓ load (supabase dashboard or dashboard/load_data.py)
Supabase PostgreSQL  (9 tables, FKs, indexes)
        ↓ sql/02  data-quality checks
        ↓ sql/03–07  analytical SQL
        ↓ sql/08  vw_* database views
        ↓
Streamlit dashboard  (dashboard/app.py)
        ↓
GitHub documentation (README + docs/)
```

## 5. Technology stack

PostgreSQL · Supabase · SQL (window functions, `FILTER`, CTEs) · Python ·
pandas · psycopg2 · Streamlit · Git/GitHub.

## 6. Repository structure

```text
olist-customer-payment-dashboard/
├── README.md
├── LICENSE
├── .gitignore
├── .env.example
├── sql/
│   ├── 01_database_setup.sql          DDL + load instructions
│   ├── 02_data_quality_checks.sql     validation queries
│   ├── 03_kpi_queries.sql             headline KPIs
│   ├── 04_payment_analysis.sql        payment types + installments
│   ├── 05_customer_analysis.sql       top customers / states / concentration
│   ├── 06_product_analysis.sql        top categories
│   ├── 07_review_analysis.sql         customer experience
│   └── 08_dashboard_views.sql         vw_* views
├── docs/
│   ├── project-overview.md
│   ├── data-dictionary.md
│   ├── database-schema.md
│   ├── methodology.md
│   └── dashboard-guide.md
├── dashboard/
│   ├── app.py                         Streamlit app
│   ├── load_data.py                   CSV → Supabase loader
│   └── requirements.txt
├── screenshots/                       dashboard.png (add after running)
└── data/                              place raw CSVs here locally (gitignored)
```

## 7. Database schema & relationships

Full detail: `docs/database-schema.md`. Summary:

```text
customers (customer_id PK) ──orders──> order_payments / order_items / order_reviews
order_items ──> products ──> product_category_name_translation
order_items ──> sellers
customers / sellers ──zip──> geolocation   (optional, not on main dashboard)
```

**Critical cardinality rules** (protect you from double-counting):

- **orders 1──n payments** — never assume 1 order = 1 payment row
  (103,886 payment rows vs 99,440 paid orders; 2,246 split-payment orders;
  2,961 orders carry multiple payment rows).
- **people ≠ customer_id** — use `customer_unique_id` (96,096) for customer
  metrics, not `customer_id` (99,441).
- **orders 1──n order_items** — never join order_items and order_payments to
  sum money in one query.
- **orders 0..n reviews** — an order can have several reviews.

## 8. Data quality

Ran on the real dataset (`sql/02_data_quality_checks.sql`):

| Check | Result |
|---|---|
| Row counts | customers 99,441 · orders 99,441 · items 112,650 · payments 103,886 · reviews 99,224 · products 32,951 · sellers 3,095 · geo ~1,000,163 · translation 71 |
| PK duplicates | 0 on customers/orders/items/payments/products/sellers; **789 reused `review_id`** in reviews (source quirk: same review content attached to 2 different orders → `review_id` is not a PK; grain = review row per order occurrence) |
| Nulls on critical columns | 0 (payment_value, customer_unique_id, price) |
| Non-positive payment values | 9 rows of 0.00 (voucher / `not_defined`), no negatives |
| Orders without payment | 1 (flagged; excluded from paid-order metrics) |
| Orphan payments / items | 0 (FK-clean) |
| Split-payment orders | 2,246 (handled via grain-aware aggregation) |
| Review score range | 1–5 range valid; 0 duplicate (review_id, order_id) rows; 789 review_id values reused across orders (documented) |
| Order status | delivered 96,478 (97.0%); shipped 1,107; canceled 625; unavailable 609; invoiced 314; processing 301; created 5; approved 2 |

## 9. Methodology (every metric traceable)

Definitions, formulas, and grain rules in `docs/methodology.md`. Summary table:

| KPI | Definition | Formula | Validation benchmark |
|---|---|---|---|
| Total payment value | money paid | SUM(payment_value) | R$16,008,872.12 |
| Total orders | all orders | COUNT(DISTINCT order_id) | 99,441 |
| Paid orders | orders with payment | COUNT(DISTINCT order_id) on payments | 99,440 |
| Unique customers | people | COUNT(DISTINCT customer_unique_id) | 96,096 |
| Average order value | per paid order | payment total ÷ paid orders | R$160.99 |
| Avg review score | satisfaction | AVG(review_score) | 4.09 |
| % high-rated | ≥4/5 | COUNT(*) FILTER (score≥4)/COUNT(*) | 77.07% |

> Benchmarks are **validation targets only**. SQL/views compute live values;
> if they diverge, investigate — never hard-code these numbers.

## 10. Payment analysis (`sql/04`)

| payment_type | orders | value | value share |
|---|---|---|---|
| credit_card | 76,505 | R$12,542,084.19 | 78.34% |
| boleto | 19,784 | R$2,869,361.27 | 17.92% |
| voucher | 3,866 | R$379,436.87 | 2.37% |
| debit_card | 1,528 | R$217,989.79 | 1.36% |

- **51.5%** of paid orders use installments (order level; the "≈49%" figure is
  the payment-row level because of split payments).
- Most common plans by order count: 1× (49,060), 2× (12,389), 3× (10,443).

## 11. Customer analysis (`sql/05`)

- **Top 5 customers by spend:** R$13,664.08 · R$9,553.02 · R$7,571.63 ·
  R$7,274.88 · R$6,929.31.
- **Concentration:** Top-5 customers = **0.28%** of value → highly distributed
  B2C base (key-account risk is low). Top-5 **states** = **73.19%** of value.
- **Top 5 states by payment:** SP R$5,998,226.96 · RJ R$2,144,379.69 ·
  MG R$1,872,257.26 · RS R$890,898.54 · PR R$811,156.38.

## 12. Product analysis (`sql/06`)

Top 5 categories by product revenue (`SUM(order_items.price)` — never confused
with payment value):

1. health_beauty — R$1,258,681.34 (8,836 orders)
2. watches_gifts — R$1,205,005.68 (5,624)
3. bed_bath_table — R$1,036,988.68 (9,417)
4. sports_leisure — R$988,048.97 (7,720)
5. computers_accessories — R$911,954.32 (6,689)

Top category share: **9.3%** of product revenue (well-spread market).

## 13. Customer experience (`sql/07`)

- Average review score **4.09 / 5** (per review; per-order method gives the
  same result).
- **77.07%** of reviews are ≥ 4/5.

## 14. Dashboard design principle

The dashboard intentionally contains **7 views only** and surfaces numbers that
answer the questions in section 3. No raw data, no maps, no bulky tables.
Rationale documented in `docs/dashboard-guide.md` (the 20-second test).

## 15. How to run

1. **Prepare Supabase**: create a project; run `sql/01_database_setup.sql`.
2. **Load data**: place the Olist CSVs in `data/`, then either use the
   Supabase CSV importer or:
   ```bash
   pip install -r dashboard/requirements.txt
   python dashboard/load_data.py --csv-dir data
   ```
3. **Validate**: run `sql/02_data_quality_checks.sql` and compare with §8.
4. **Build analysis**: run `sql/03…07` (optional — reusable), then
   `sql/08_dashboard_views.sql`.
5. **Dashboard**:
   ```bash
   streamlit run dashboard/app.py
   ```

## 16. Environment variables

`.env.example` documents `SUPABASE_DATABASE_URL`. Copy it to `.env`, fill in the
real value, and **never commit `.env`**. No credentials appear anywhere in the
repository.

## 17. Traceability map

| Dashboard element | View | Source tables | Calculation |
|---|---|---|---|
| Total payment / paid orders | vw_dashboard_kpis | order_payments | SUM(value), COUNT(DISTINCT order_id) |
| Orders / delivered | vw_dashboard_kpis | orders | COUNT(DISTINCT order_id) |
| Unique customers | vw_dashboard_kpis | customers | COUNT(DISTINCT unique_id) |
| Avg order value | vw_dashboard_kpis | order_payments | total ÷ paid orders |
| Avg rating / % high-rated | vw_dashboard_kpis | order_reviews | AVG(score), % ≥4 |
| Payment methods | vw_payment_summary | order_payments | GROUP BY payment_type |
| Installments | vw_installment_summary | order_payments | GROUP BY installments |
| Top customers | vw_top_customers | customers/orders/payments | ORDER BY spend DESC LIMIT 5 |
| Top states | vw_top_customer_states | customers/orders/payments | GROUP BY state |
| Top categories | vw_top_product_categories | items/products/translation | GROUP BY category |
| Experience card | vw_customer_experience | order_reviews | AVG + % |

## 18. Key insights (validated from the data)

1. **Credit card dominates** — ~78% of payment value.
2. **Geography concentrates value** — top 5 states hold ~73%; SP alone ~37%.
3. **Broad B2C base** — top 5 customers are only ~0.28% of value.
4. **Installments are mainstream** — >51% of paid orders; 2× is the most
   common multi-installment plan.
5. **health_beauty leads categories** at ~9.3% of product revenue.
6. **Customers are satisfied** — 4.09/5 average, 77% ≥4/5.

## 19. Limitations

- One order in the source has no payment record (excluded from payment KPIs).
- Order-value date coverage only through Oct 2018; dataset is historical.
- `not_defined` payment rows (value 0) are excluded from visuals.
- Geolocation and seller richness are not exploited on the main dashboard.

## 20. Future improvements

- Monthly payment trend (single line, Top 5 only) and seasonality.
- Delivery-time vs review-score analysis.
- Seller concentration drill-down on a supporting page.
- Parametrized filters (state/category) with the same 20-second discipline.

## 21. Team members

[Add team member names and roles here]

---

_Data: Olist Brazilian E-commerce Public Dataset. Money in BRL. Numbers marked
"≈" are validation benchmarks from the full-dataset audit (see section 9)._