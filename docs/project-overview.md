# Project Overview

Olist is a Brazilian marketplace connecting ~100k small merchants to customers
across Brazil. This project builds a **Customer & Payment Analytics Dashboard**
from the public Olist dataset (~2016–2018), designed to be understood in
**under 20 seconds**.

## Business problem

The business has thousands of orders, 96,000+ unique customers and R$16M in
payments. Management asked for a **compact, aggregated view** — not a bulky
analytics portal — that answers, from a customer point of view:

> How much money do we take? How do customers pay? Who are the top customers
> and where are they? What do they buy, and are they satisfied?

## Design constraints (from the staff brief)

- **Not bulky / no huge visualisations.** Only highlighted, aggregated facts.
- **Top 5 lists** with proper aggregation and `ORDER BY` (pivot tables approved).
- Payment information is the centerpiece.
- A viewer must grasp the main story in **≤ 20 seconds**.

## Deliverables

- Supabase (PostgreSQL) database with the validated Olist schema.
- Executable SQL: data-quality checks, KPIs, payment/customer/product/review
  analysis, and dashboard views (`vw_*`).
- A Streamlit dashboard reading **only** the `vw_*` views.
- This GitHub repository with full documentation and traceability.

## Key questions answered

1. Total value paid, orders, and unique customers.
2. Payment-type mix and installment behavior.
3. Top 5 customers by spend and customer concentration.
4. Top 5 customer states by payment value.
5. Top 5 product categories by revenue.
6. Customer satisfaction (review score).
7. The actionable insights that fall out of the numbers above.