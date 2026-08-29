"""Analytical queries for the Olist dashboard.

All queries read from the ``vw_*`` analytical views that were validated
against the independent CSV audit.  No hard-coded dashboard numbers are
present — every value is produced by a PostgreSQL query at run time.

The module is intentionally thin: it only contains SQL and very minor
Python helpers.  Formatting is in ``formatting.py``.
"""

from dashboard.db import run_query, run_scalar


# ---------------------------------------------------------------------
# KPI row (the 5 cards that appear at the top of the dashboard)
# ---------------------------------------------------------------------
def kpi() -> dict:
    """Return the headline KPIs as a dict of ``str`` -> ``str/number``."""
    sql = "SELECT * FROM vw_dashboard_kpis;"
    rows = run_query(sql)
    if not rows:
        return {}
    return dict(zip(rows[0].keys(), rows[0]))


# ---------------------------------------------------------------------
# Payment summary — one row per payment type
# ---------------------------------------------------------------------
def payment_summary() -> list[dict]:
    """Return one dict per payment type ordered by total value DESC."""
    sql = "SELECT * FROM vw_payment_summary ORDER BY total_payment_value DESC;"
    return run_query(sql)


# ---------------------------------------------------------------------
# Installment distribution — top 6 installment plans
# ---------------------------------------------------------------------
def installment_distribution() -> list[dict]:
    """Return the top 6 installment plans by order count."""
    sql = "SELECT * FROM vw_installment_summary ORDER BY order_count DESC LIMIT 6;"
    return run_query(sql)


# ---------------------------------------------------------------------
# Top 5 customers (by spend)
# ---------------------------------------------------------------------
def top_customers() -> list[dict]:
    """Return the top 5 customers with rank, ref, order count, spend."""
    sql = "SELECT * FROM vw_top_customers;"
    return run_query(sql)


# ---------------------------------------------------------------------
# Top 5 customer states (by payment value)
# ---------------------------------------------------------------------
def top_customer_states() -> list[dict]:
    """Return the top 5 states with rank, state, customers, orders, value."""
    sql = "SELECT * FROM vw_top_customer_states;"
    return run_query(sql)


# ---------------------------------------------------------------------
# Top 5 product categories (by product revenue)
# ---------------------------------------------------------------------
def top_product_categories() -> list[dict]:
    """Return the top 5 categories with rank, category, items_sold, orders, revenue."""
    sql = "SELECT * FROM vw_top_product_categories;"
    return run_query(sql)


# ---------------------------------------------------------------------
# Customer experience (small card)
# ---------------------------------------------------------------------
def customer_experience() -> dict:
    """Return review count, orders with reviews, avg score, % high-rated."""
    sql = "SELECT * FROM vw_customer_experience;"
    rows = run_query(sql)
    return rows[0] if rows else {}


# ---------------------------------------------------------------------
# Dynamic views — filter-aware (used when filters are applied)
# ---------------------------------------------------------------------
def payment_summary_dynamic(
    start_date: str | None = None,
    end_date: str | None = None,
    payment_type: str | None = None,
    customer_state: str | None = None,
) -> list[dict]:
    """Return payment summary filtered by the given parameters.

    The underlying view ``vw_payment_summary_dynamic`` accepts WHERE‑clause
    conditions that are safely injected from this wrapper; the SQL itself
    never concatenates raw user strings.
    """
    base = "SELECT * FROM vw_payment_summary_dynamic WHERE 1=1"
    conditions: list[str] = []
    params: list = []

    if start_date:
        conditions.append("o.order_purchase_timestamp >= %s")
        params.append(start_date)
    if end_date:
        conditions.append("o.order_purchase_timestamp <= %s")
        params.append(end_date)
    if payment_type:
        conditions.append("p.payment_type = %s")
        params.append(payment_type)
    if customer_state:
        conditions.append("c.customer_state = %s")
        params.append(customer_state)

    if conditions:
        sql = f"{base} AND {' AND '.join(conditions)}"
    else:
        sql = base

    return run_query(sql)


def installment_distribution(
    start_date: str | None = None,
    end_date: str | None = None,
) -> list[dict]:
    """Return installment distribution optionally filtered by date range."""
    base = "SELECT * FROM vw_installment_distribution WHERE 1=1"
    conditions: list[str] = []
    params: list = []

    if start_date:
        conditions.append("o.order_purchase_timestamp >= %s")
        params.append(start_date)
    if end_date:
        conditions.append("o.order_purchase_timestamp <= %s")
        params.append(end_date)

    if conditions:
        sql = f"{base} AND {' AND '.join(conditions)}"
    else:
        sql = base

    return run_query(sql)


def monthly_payment_trend(
    start_date: str | None = None,
    end_date: str | None = None,
) -> list[dict]:
    """Return monthly payment trend optionally filtered by date range."""
    base = "SELECT * FROM vw_monthly_payment_trend WHERE 1=1"
    conditions: list[str] = []
    params: list = []

    if start_date:
        conditions.append("month_start >= %s")
        params.append(start_date)
    if end_date:
        conditions.append("month_start <= %s")
        params.append(end_date)

    if conditions:
        sql = f"{base} AND {' AND '.join(conditions)}"
    else:
        sql = base

    return run_query(sql)


def quarterly_payment_trend(
    start_date: str | None = None,
    end_date: str | None = None,
) -> list[dict]:
    """Return quarterly payment trend optionally filtered by date range."""
    base = "SELECT * FROM vw_quarterly_payment_trend WHERE 1=1"
    conditions: list[str] = []
    params: list = []

    if start_date:
        conditions.append("quarter_start >= %s")
        params.append(start_date)
    if end_date:
        conditions.append("quarter_start <= %s")
        params.append(end_date)

    if conditions:
        sql = f"{base} AND {' AND '.join(conditions)}"
    else:
        sql = base

    return run_query(sql)


def customer_segments() -> list[dict]:
    """Return customer segmentation (one-time vs repeat)."""
    sql = "SELECT * FROM vw_customer_segments;"
    return run_query(sql)


def customer_segment_detail() -> list[dict]:
    """Return customer segment detail (1 order, 2 orders, 3 orders, etc.)."""
    sql = "SELECT * FROM vw_customer_segment_detail;"
    return run_query(sql)


def top_sellers() -> list[dict]:
    """Return the top 5 sellers by product revenue."""
    sql = "SELECT * FROM vw_top_sellers;"
    return run_query(sql)


def order_status_summary() -> list[dict]:
    """Return order status counts and shares."""
    sql = "SELECT * FROM vw_order_status_summary;"
    return run_query(sql)


def delivery_performance() -> dict:
    """Return delivery performance metrics."""
    sql = "SELECT * FROM vw_delivery_performance;"
    rows = run_query(sql)
    return rows[0] if rows else {}


def review_score_distribution() -> list[dict]:
    """Return review score distribution."""
    sql = "SELECT * FROM vw_review_score_distribution;"
    return run_query(sql)


def repeat_customer_rate() -> dict:
    """Return repeat customer rate."""
    sql = "SELECT * FROM vw_repeat_customer_rate;"
    rows = run_query(sql)
    return rows[0] if rows else {}


# ---------------------------------------------------------------------
# Helpers that compute a few extra metrics on top of the baseline views.
# ---------------------------------------------------------------------
def paid_order_rate() -> float:
    """Paid orders / total orders (as a percentage)."""
    k = kpi()
    total = k.get("total_orders", 0)
    paid = k.get("total_paid_orders", 0)
    if total == 0:
        return 0.0
    return round(100.0 * paid / total, 2)


def avg_freight() -> float:
    """Average freight value per order item."""
    sql = "SELECT ROUND(AVG(freight_value)::numeric, 2) FROM order_items;"
    return run_scalar(sql)


def high_rated_review_pct() -> float:
    """Percentage of reviews with score >= 4 (same as kpi pct_high_rated_reviews)."""
    k = kpi()
    return k.get("pct_high_rated_reviews", 0.0)


def top5_customer_share() -> float:
    """Top 5 customers share of total payment value."""
    k = kpi()
    return k.get("top5_customer_share_pct", 0.0)


def top5_state_share() -> float:
    """Top 5 states share of total payment value."""
    k = kpi()
    return k.get("top5_state_share_pct", 0.0)


def top_category_share() -> float:
    """Top category share of product revenue."""
    k = kpi()
    return k.get("top_category_share_pct", 0.0)


def total_payment_value() -> float:
    """Total payment value from the KPI view."""
    k = kpi()
    v = k.get("total_payment_value", 0)
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0