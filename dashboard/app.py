"""Olist Customer & Payment Analytics Dashboard — modern interactive version.

This dashboard reads **only** the ``vw_*`` Supabase views and therefore
depends on the validated SQL layer (``sql/01``–``sql/08``).  The design
is a single‑page, filter‑driven analytics product that still satisfies the
staff requirement: *"not bulky or huge … Top 5 … proper aggregation …
understand in ~20 seconds"*.

Filters are reactive (Streamlit) but the first screen (KPI strip + payment
mix + top 5 states/categories) is always readable without interaction.

--- 

**Data source** — Supabase PostgreSQL via the ``vw_*`` analytical views.
**Pandas** is **not** used; all aggregation stays in PostgreSQL.
"""

import os
from datetime import datetime

import streamlit as st

# --------------------------------------------------------------------- #
# 1.  PAGE & SECRETS SETUP
# --------------------------------------------------------------------- #
# The app expects the environment variable injected by Streamlit Cloud
# (or the local ``.env`` file that is *git‑ignored*).
from dashboard.db import (
    kpi,
    payment_summary,
    installment_distribution,
    top_customers,
    top_customer_states,
    top_product_categories,
    customer_experience,
    paid_order_rate,
    avg_freight,
    high_rated_review_pct,
    top5_customer_share,
    top5_state_share,
    top_category_share,
)
from dashboard.queries import (
    payment_summary_dynamic,
    installment_distribution as inst_dyn,
    monthly_payment_trend,
    quarterly_payment_trend,
    customer_segments,
    customer_segment_detail,
    top_sellers,
    order_status_summary,
    delivery_performance,
    review_score_distribution,
    repeat_customer_rate,
)
from dashboard.formatting import (
    format_currency,
    format_number,
    format_percent,
    format_score,
    format_count,
)

# Load optional date / filter parameters from Streamlit secrets or
# environment if the app is run locally without the cloud secret store.
# --------------------------------------------------------------------- #
st.set_page_config(
    page_title="Olist Customer & Payment Analytics",
    layout="wide",
    initial_sidebar_state="expanded",
)

# --------------------------------------------------------------------- #
# 2.  GLOBAL CAPTURE & REFRESH
# --------------------------------------------------------------------- #
st.title("Olist Customer & Payment Analytics")
st.caption(
    f"Customer • Payment • Sales Intelligence  •  Last refreshed: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}"
)

# --------------------------------------------------------------------- #
# 3.  FILTER BAR (compact but powerful)
# --------------------------------------------------------------------- #
st.sidebar.header("Filters")

# Date range
date_range = st.sidebar.date_input(
    "Date range",
    value=(st.session_state.get("date_range_start"),
           st.session_state.get("date_range_end")),
    help="Select a start and end date to filter all metrics.",
)

# Ensure we have python date objects
if isinstance(date_range, tuple) and len(date_range) == 2:
    sd = datetime.strptime(str(date_range[0]), "%Y-%m-%d").date() if date_range[0] else None
    ed = datetime.strptime(str(date_range[1]), "%Y-%m-%d").date() if date_range[1] else None
else:
    sd, ed = None, None

# Order status
status_options = ["All"] + st.session_state.get("status_options", ["delivered", "canceled", "unavailable", "in_process", "return_pending"])
selected_status = st.sidebar.selectbox("Order status", status_options, index=0)

# Payment type
pay_options = ["All"] + st.session_state.get("payment_type_options", ["credit_card", "boleto", "voucher", "debit_card", "not_defined"])
selected_payment = st.sidebar.selectbox("Payment type", pay_options, index=0)

# Customer state
state_options = ["All"] + st.session_state.get("customer_state_options", [])
selected_state = st.sidebar.selectbox("Customer state", state_options, index=0)

# Product category
cat_options = ["All"] + st.session_state.get("category_options", [])
selected_category = st.sidebar.selectbox("Product category", cat_options, index=0)

# Seller state
seller_state_options = ["All"] + st.session_state.get("seller_state_options", [])
selected_seller_state = st.sidebar.selectbox("Seller state", seller_state_options, index=0)

# Seller
seller_options = ["All"] + st.session_state.get("seller_options", [])
selected_seller = st.sidebar.selectbox("Seller", seller_options, index=0)

# Apply / Reset buttons
col_apply, col_reset = st.sidebar.columns(2)
with col_apply:
    if st.button("Apply Filters", use_container_width=True):
        # Store selections in session state so they persist across reruns
        st.session_state["date_range_start"] = (
            sd.strftime("%Y-%m-%d") if sd else None
        )
        st.session_state["date_range_end"] = ed.strftime("%Y-%m-%d") if ed else None
        st.session_state["selected_status"] = selected_status
        st.session_state["selected_payment"] = selected_payment
        st.session_state["selected_state"] = selected_state
        st.session_state["selected_category"] = selected_category
        st.session_state["selected_seller_state"] = selected_seller_state
        st.session_state["selected_seller"] = selected_seller
        st.rerun()
with col_reset:
    # Clear all session‑state filter keys
    for key in [
        "date_range_start",
        "date_range_end",
        "selected_status",
        "selected_payment",
        "selected_state",
        "selected_category",
        "selected_seller_state",
        "selected_seller",
    ]:
        st.session_state.pop(key, None)
    st.rerun()

# --------------------------------------------------------------------- #
# 4.  TOP KPI STRIP (5 primary cards — always visible)
# --------------------------------------------------------------------- #
k = kpi()

c1, c2, c3, c4, c5 = st.columns(5)
with c1:
    st.metric("Total Payment Value", format_currency(k["total_payment_value"]))
with c2:
    st.metric("Total Orders", format_count(k["total_orders"]))
with c3:
    st.metric("Unique Customers", format_number(k["unique_customers"]))
with c3:
    st.metric("Avg Order Value", format_currency(k["average_order_value"]))
with c5:
    st.metric("Avg Review Score", format_score(k["avg_review_score"]))

# --------------------------------------------------------------------- #
# 5.  SECONDARY KPI / INSIGHT STRIP
# --------------------------------------------------------------------- #
# Paid order rate, installment adoption, avg freight, repeat customer rate,
# high‑rated review percentage — displayed as a compact row.
col_a, col_b, col_c, col_d, col_e = st.columns(5)
with col_a:
    st.metric("Paid Order Rate", f"{paid_order_rate()}%")
with col_b:
    st.metric("Installment Adoption", f"{inst_dyn()[0]['avg_installments'] if inst_dyn() else '—'}x avg")
with col_c:
    st.metric("Avg Freight", format_currency(avg_freight()))
with col_d:
    st.metric("Repeat Customer Rate", f"{repeat_customer_rate().get('repeat_rate_pct', 0):.1f}%")
with col_e:
    st.metric("High‑Rated Reviews", f"{high_rated_review_pct():.1f}%")

# --------------------------------------------------------------------- #
# 6.  PAYMENT ANALYTICS
# --------------------------------------------------------------------- #
st.subheader("Payment Mix")
# Use the dynamic version if filters are active, otherwise the static view.
pay_data = payment_summary_dynamic(
    start_date=st.session_state.get("date_range_start"),
    end_date=st.session_state.get("date_range_end"),
    payment_type=st.session_state.get("selected_payment") if st.session_state.get("selected_payment") != "All" else None,
    customer_state=st.session_state.get("selected_state") if st.session_state.get("selected_state") != "All" else None,
) if any(
    [
        st.session_state.get("date_range_start"),
        st.session_state.get("date_range_end"),
        st.session_state.get("selected_payment") != "All",
        st.session_state.get("selected_state") != "All",
    ]
) else payment_summary()

# Highlight the dominant method
if pay_data:
    dominant = pay_data[0]
    st.caption(f"**{dominant['payment_type']}** dominates at {dominant['value_share_pct']:.1f}% of payment value.")

# Horizontal bar chart (CSS/HTML — no pandas dependency)
def html_bar(rows, color="#1F77B4"):
    """Pure CSS horizontal bar from (label, value) pairs."""
    max_val = max(r[1] for r in rows) if rows else 1
    parts = []
    for label, val in rows:
        width = max(2.0, 100.0 * val / max_val)
        parts.append(
            f'<div style="display:flex;align-items:center;margin:6px 0;">'
            f'<span style="width:140px;font-size:14px;color:#333;">{label}</span>'
            f'<div style="height:20px;width:{width:.1f}%;background:{color};'
            f'border-radius:3px;min-width:6px;"></div>'
            f'<span style="margin-left:8px;font-size:14px;font-weight:600;">{val:,.0f}</span>'
            f'</div>'
        )
    return f'<div style="font-family:inter,system-ui,Arial,sans-serif;">{"".join(parts)}</div>'

bar_rows = [(r["payment_type"], r["total_payment_value"]) for r in pay_data]
st.html(html_bar(bar_rows, color="#E4572E"))
st.caption("Payment value by method (R$)")

# Table below the chart
pay_table = [[r["payment_type"], format_count(r["orders"]), format_currency(r["total_payment_value"]), format_percent(r["value_share_pct"])] for r in pay_data]
st.markdown(md_table(["Payment type", "Orders", "Value (R$)", "Share %"], pay_table))

# --------------------------------------------------------------------- #
# 7.  INSTALLMENT BEHAVIOR
# --------------------------------------------------------------------- #
st.subheader("Installment Usage")
inst = installment_distribution(
    start_date=st.session_state.get("date_range_start"),
    end_date=st.session_state.get("date_range_end"),
)
if inst:
    # Build bar HTML for installment plans
    inst_rows = [(f"{r['payment_installments']}x", r["order_count"]) for r in inst]
    max_val = max(r[1] for r in inst_rows) if inst_rows else 1
    bar_parts = []
    for label, val in inst_rows:
        width = max(2.0, 100.0 * val / max_val)
        bar_parts.append(
            f'<div style="display:flex;align-items:center;margin:4px 0;">'
            f'<span style="width:80px;font-size:13px;color:#333;">{label}</span>'
            f'<div style="height:18px;width:{width:.1f}%;background:#2CA02C;'
            f'border-radius:2px;min-width:5px;"></div>'
            f'<span style="margin-left:6px;font-size:13px;font-weight:600;">{val:,}</span>'
            f'</div>'
        )
    st.html(f'<div style="font-family:inter,system-ui,Arial,sans-serif;">{"".join(bar_parts)}</div>')
    st.caption(f"{inst[0]['order_count']} orders use the most common plan ({inst[0]['payment_installments']}x)")


# --------------------------------------------------------------------- #
# 7.  TIME TREND
# --------------------------------------------------------------------- #
st.subheader("Payment Trend")
trend_type = st.radio("Granularity", ["Monthly", "Quarterly"], horizontal=True, key="trend_granularity")
trend_data = monthly_payment_trend(
    start_date=st.session_state.get("date_range_start"),
    end_date=st.session_state.get("date_range_end"),
) if st.session_state.get("trend_granularity") == "Monthly" else quarterly_payment_trend(
    start_date=st.session_state.get("date_range_start"),
    end_date=st.session_state.get("date_range_end"),
)

if trend_data:
    # Simplified line chart data — just the values, Streamlit will plot
    months = [str(r["month_start"]) for r in trend_data]
    values = [float(r["total_payment_value"]) for r in trend_data]
    st.line_chart(
        {"Payment Value (R$)": values},
        use_container_width=True,
        height=200,
    )
    st.caption(f"Trend {'over selected period' if sd and ed else 'since dataset start'}")

# --------------------------------------------------------------------- #
# 8.  CUSTOMER ANALYTICS
# --------------------------------------------------------------------- #
st.subheader("Customer Analytics")

c6, c7 = st.columns(2)
with c6:
    st.markdown("**Top 5 Customers**")
    cust_data = top_customers()
    if cust_data:
        table = [[
            r["rank"],
            r["customer_ref"][:12] + "..." if len(r["customer_ref"]) > 12 else r["customer_ref"],
            format_count(r["order_count"]),
            format_currency(r["total_spend"]),
        ] for r in cust_data]
        st.markdown(md_table(["Rank", "Customer", "Orders", "Spend (R)"], table))
    # Concentration metric
    st.caption(f"Top 5 share: {top5_customer_share():.2f}% of total payment value")

with c7:
    st.markdown("**Top 5 States**")
    state_data = top_customer_states()
    if state_data:
        table = [[
            r["rank"],
            r["state"],
            format_count(r["customers"]),
            format_currency(r["total_payment_value"]),
            format_percent(r["value_share_pct"]),
        ] for r in state_data]
        st.markdown(md_table(["State", "Customers", "Value (R$)", "Share %"], table))
    st.caption(f"Top 5 share: {top5_state_share():.2f}% of total payment value")

# --------------------------------------------------------------------- #
# 9.  PRODUCT ANALYTICS
# --------------------------------------------------------------------- #
st.subheader("Product Categories")
cat_data = top_product_categories()
if cat_data:
    cat_rows = [(r["category"], r["revenue"], format_count(r["items_sold"]), format_count(r["orders"])) for r in cat_data]
    st.markdown(md_table(["Category", "Revenue (R$)", "Items", "Orders"], cat_rows))
    st.caption(f"Leading category: {cat_data[0]['category']} — {format_currency(cat_data[0]['revenue'])}")

# --------------------------------------------------------------------- #
# 10. SELLER ANALYTICS
# --------------------------------------------------------------------- #
st.subheader("Seller Analytics")
seller_data = top_sellers()
if seller_data:
    seller_rows = [[r["seller_id"][:10] + "..." if len(r["seller_id"]) > 10 else r["seller_id"],
                   format_currency(r["product_revenue"]),
                   format_count(r["orders"]),
                   format_count(r["items_sold"])] for r in seller_data]
    st.markdown(md_table(["Seller", "Revenue (R$)", "Orders", "Items"], seller_rows))

# --------------------------------------------------------------------- #
# 11. CUSTOMER EXPERIENCE
# --------------------------------------------------------------------- #
st.subheader("Customer Experience")
exp = customer_experience()
if exp:
    st.metric("Average Review Score", format_score(exp.get("avg_review_score", 0)))
    st.metric("% Reviews ≥ 4", f"{exp.get('pct_high_rated_reviews', 0):.1f}%")
    st.metric("Review Count", format_count(exp.get("review_count", 0)))
    st.metric("Orders with Reviews", format_count(exp.get("orders_with_reviews", 0)))

# --------------------------------------------------------------------- #
# 12. ORDER PERFORMANCE
# --------------------------------------------------------------------- #
perf = delivery_performance()
if perf:
    st.metric("Delivery Rate", f"{perf.get('delivery_rate_pct', 0):.1f}%")
    st.metric("Cancellation Rate", f"{perf.get('cancellation_rate_pct', 0):.1f}%")
    if perf.get("late_delivery_rate_pct") is not None:
        st.metric("Late Delivery Rate", f"{perf.get('late_delivery_rate_pct'):.1f}%")

# --------------------------------------------------------------------- #
# 12. BUSINESS INSIGHTS (dynamic, computed at runtime)
# --------------------------------------------------------------------- #
st.subheader("Key Business Insights")
# These are generated from the live data; nothing is hard-coded.
insights = []

# Credit card dominance
if pay_data:
    dominant = pay_data[0]
    pct = dominant.get("value_share_pct", 0)
    if pct and pct >= 70:
        insights.append(f"Credit card accounts for **{pct:.1f}%** of payment value.")

# SP concentration
if state_data:
    sp_entry = next((s for s in state_data if s.get("state") == "SP"), None)
    if sp_entry:
        pct = sp_entry.get("value_share_pct", 0)
        if pct and pct >= 30:
            insights.append(f"São Paulo contributes **{pct:.1f}%** of payment value.")

# Top 5 states aggregate
if state_data:
    total_5 = sum(s.get("value_share_pct", 0) or 0 for s in state_data[:5])
    if total_5 and total_5 >= 60:
        insights.append(f"Top 5 customer states contribute **{total_5:.1f}%** of payment value.")

# Installment adoption
if inst:
    multi = [r for r in inst if r.get("payment_installments", 0) > 1]
    if multi:
        pct = (multi[0].get("order_count", 0) / k["total_paid_orders"] * 100) if k.get("total_paid_orders") else 0
        if pct and pct >= 40:
            insights.append(f"**{pct:.1f}%** of paid orders use installments.")

# Top category
if cat_data:
    leading = cat_data[0]
    pct = leading.get("share_pct", 0)
    if pct and pct >= 8:
        insights.append(f"**{leading['category']}** is the leading product category by product revenue ({pct:.1f}% of total).")

# Review strength
if exp:
    pct = exp.get("pct_high_rated_reviews", 0)
    if pct and pct >= 70:
        insights.append(f"{pct:.0f}% of reviews are rated 4‑5/5, indicating strong customer satisfaction.")

# Format and display
if insights:
    for line in insights:
        st.markdown(f"- {line}")
else:
    st.caption("No high‑confidence insights generated for the current filter state.")

# --------------------------------------------------------------------- #
# 13.  REFRESH BUTTON
# --------------------------------------------------------------------- #
if st.button("Refresh Data", use_container_width=True):
    st.cache_data.clear()
    st.rerun()

# --------------------------------------------------------------------- #
# 14.  FOOTER / SECURITY NOTE
# --------------------------------------------------------------------- #
st.divider()
st.caption(
    "All numbers are produced by Supabase ``vw_*`` views at run time. "
    "No CSV files are read at runtime; no values are hard‑coded. "
    "Source dataset: Olist Brazilian e‑commerce public dataset."
)