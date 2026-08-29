import os

import psycopg2
import streamlit as st

st.set_page_config(page_title="Olist Customer & Payment Dashboard", layout="wide")

DATABASE_URL = os.environ.get("SUPABASE_DATABASE_URL")
if not DATABASE_URL:
    st.error("Set SUPABASE_DATABASE_URL in your environment (.env or shell).")


def query(sql):
    """Run a SELECT against the views; return (column_names, [rows])."""
    with psycopg2.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            names = [d[0] for d in cur.description]
            rows = cur.fetchall()
    return names, rows


def money(x):
    return f"R$ {x:,.0f}"


def bars_html(rows, color="#1F77B4"):
    """rows: list of (label, display_value). Pure CSS horizontal bars."""
    max_val = max(r[1] for r in rows) if rows else 1
    out = ['<div style="font-family:inherit">']
    for label, val in rows:
        width = max(2.0, 100.0 * val / max_val)
        out.append(
            '<div style="display:flex;align-items:center;margin:5px 0;">'
            f'<span style="width:200px;font-size:14px;color:#333;">{label}</span>'
            f'<div style="height:22px;width:{width:.1f}%;background:{color};'
            'border-radius:3px;min-width:6px;"></div>'
            '<span style="margin-left:10px;font-size:14px;font-weight:600;">'
            f"{val:,}</span></div>"
        )
    out.append("</div>")
    return "".join(out)


def md_table(headers, rows):
    markdown = "| " + " | ".join(headers) + " |\n"
    markdown += "|" + "|".join(["---"] * len(headers)) + "|\n"
    for r in rows:
        markdown += "| " + " | ".join(str(c) for c in r) + " |\n"
    return markdown


def main():
    # ---- fetch everything from the vw_* views (no hard-coded values) ----
    k_names, k_rows = query("SELECT * FROM vw_dashboard_kpis;")
    k = dict(zip(k_names, k_rows[0]))
    _, pay = query("SELECT * FROM vw_payment_summary ORDER BY total_payment_value DESC;")
    _, inst = query("SELECT * FROM vw_installment_summary ORDER BY order_count DESC;")
    _, cust = query("SELECT * FROM vw_top_customers;")
    _, state = query("SELECT * FROM vw_top_customer_states;")
    _, cat = query("SELECT * FROM vw_top_product_categories;")

    pay = [r for r in pay if r[0] != "not_defined"]

    st.title("Olist — Customer & Payment Dashboard")
    st.caption("Aggregated view for a quick read (≤ 20 seconds). Source: Supabase views (`vw_*`).")

    # ---- KPI row (5 cards) ----
    c = st.columns(5)
    c[0].metric("Total Payment Value", money(k["total_payment_value"]))
    c[1].metric("Total Orders", f"{k['total_orders']:,}")
    c[2].metric("Unique Customers", f"{k['unique_customers']:,}")
    c[3].metric("Avg Order Value", money(k["average_order_value"]))
    c[4].metric("Avg Review Score", f"{k['avg_review_score']} / 5")

    # ---- Payment overview ----
    st.subheader("How do customers pay?")
    col_p, col_t = st.columns(2)
    with col_p:
        st.html(bars_html(
            [(f"{r[0]} · {r[3]:.1f}%", round(float(r[2]))) for r in pay],
            color="#E4572E",
        ))
        st.caption("Payment value by method (R$)")
    with col_t:
        st.markdown(md_table(
            ["Payment type", "Orders", "Value (R$)", "Share %"],
            [[r[0], f"{r[1]:,}", f"{r[2]:,.2f}", f"{r[3]:.2f}%"] for r in pay],
        ))

    # ---- Installment usage ----
    st.subheader("Installment usage")
    st.caption(f"{k['installment_order_pct']:.1f}% of paid orders use installments")
    st.html(bars_html([(f"{r[0]}x", r[1]) for r in inst], color="#2CA02C"))
    st.caption("Orders per installment plan (top 6)")

    # ---- Customer concentration + top 5 ----
    st.subheader("Customer concentration")
    c = st.columns(2)
    with c[0]:
        st.metric("Share of value, Top 5 customers", f"{k['top5_customer_share_pct']:.2f} %")
        st.caption("Highly distributed B2C base — no dominant accounts.")
    with c[1]:
        st.metric("Share of value, Top 5 states", f"{k['top5_state_share_pct']:.2f} %")
        st.caption("Payments concentrate in a few states (SP leads).")

    c = st.columns(2)
    with c[0]:
        st.markdown("**Top 5 customers by spend**")
        st.markdown(md_table(
            ["Rank", "Customer", "Orders", "Total spend (R$)"],
            [[r[0], r[1], r[2], f"{r[3]:,.2f}"] for r in cust],
        ))
    with c[1]:
        st.markdown("**Top 5 states by payment value**")
        st.markdown(md_table(
            ["Rank", "State", "Customers", "Value (R$)"],
            [[r[0], r[1], r[2], f"{r[4]:,.0f}"] for r in state],
        ))

    # ---- Top categories ----
    st.subheader("Top 5 product categories")
    st.html(bars_html(
        [(r[1], round(float(r[4]))) for r in cat], color="#2F4F4F",
    ))
    st.markdown(md_table(
        ["Rank", "Category", "Orders", "Revenue (R$)"],
        [[r[0], r[1], r[3], f"{r[4]:,.2f}"] for r in cat],
    ))

    # ---- Insights computed from live query results ----
    st.subheader("Key insights")
    top_type = pay[0]
    top_state = state[0]
    top_cat = cat[0]
    inst_multi = [r for r in inst if r[0] > 1]
    top_inst = inst_multi[0][0] if inst_multi else 1
    st.markdown(
        f"""
- `{top_type[0]}` is the dominant payment method — {top_type[3]:.1f}% of payment value.
- Payments concentrate in **{top_state[1]}** ({top_state[5]:.1f}% of value); Top-5 states hold {k['top5_state_share_pct']:.1f}%.
- Top 5 customers hold only **{k['top5_customer_share_pct']:.2f}%** of value → broad B2C base, no key-account risk.
- **{k['installment_order_pct']:.1f}%** of orders are paid in installments; **{top_inst}x** is the most common multi-installment plan.
- **{top_cat[1]}** leads product revenue at {k['top_category_share_pct']:.1f}% of the total.
- Customer satisfaction is strong: average review **{k['avg_review_score']}/5**, {k['pct_high_rated_reviews']:.0f}% of reviews ≥ 4/5.
"""
    )
    st.caption(
        "Every number is produced by a Supabase view at run time — see "
        "sql/08_dashboard_views.sql and docs/methodology.md for traceability."
    )


if __name__ == "__main__":
    main()