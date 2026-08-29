# Dashboard Guide

## The 20-second principle

The staff brief is explicit: **not bulky, only highlighted information, Top 5s,
proper aggregation, pivot-friendly, payment + customer focus, readable in
≤ 20 seconds.** Every design decision below serves that rule.

## Layout

```text
CUSTOMER & PAYMENT DASHBOARD
+--------+--------+--------+--------+----------+
| R$16.0M| 99,441 | 96,096 | R$161  | 4.09 / 5 |
| Paid   | Orders | Cust.  | AOV    | Rating   |
+--------+--------+--------+--------+----------+
How do customers pay?  (bar + compact table)
Customer concentration (2 metrics: top-5 customers vs states)
Top 5 customers | Top 5 states | Top 5 categories
Installment usage | satisfaction card
Key insights (6 bullets, computed live)
```

## What is deliberately absent

- No raw transactions, no tables with >5 rows, no maps of Brazil, no charts
  per month/city/seller, no 15-visual overload.
- No customer/seller geography maps — geolocation is optional supporting data.
- No per-product/per-seller analysis on the main page.

## Reading the dashboard (expected reading path)

1. **KPI row** — how big is the business (R$16.0M in payments, ~99.4K orders,
   96.1K customers, AOV R$161, rating 4.09).
2. **How customers pay** — credit card dominates (~78%).
3. **Concentration** — value lives in a few states (SP ~37%), but is spread
   across thousands of tiny customers (top-5 = 0.28%).
4. **Top 5s** — the best customers/states/categories at a glance.
5. **Installments** — half of orders use installments.
6. **Insights** — the six numbers that tell the story.

## Technical notes

- The app queries the `vw_*` views only; nothing is hard-coded. Edit
  `app.py` and re-run `streamlit run dashboard/app.py`.
- Values are formatted as R$ (Brazilian Real).
- Customer ids are masked (`customer_ref`, first 12 chars of the unique id)
  for display.
- The app is **pandas-free on purpose**: charts are pure CSS/HTML bars via
  `st.html`, tables are Markdown, and data comes straight from psycopg2. This
  guarantees it runs even where Windows App Control blocks pandas/pyarrow
  native DLLs (the case on the dev machine). Only `streamlit`, `psycopg2` and
  `python-dotenv` are required.

## Running

```bash
pip install -r dashboard/requirements.txt
set -a; . ./.env; set +a        # or: export $(cat .env | xargs) / equivalent
streamlit run dashboard/app.py
```

Add a screenshot under `screenshots/dashboard.png` and reference it in the
README.