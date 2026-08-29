"""Load the raw Olist CSVs into the Supabase (PostgreSQL) database.

Usage:
    pip install -r dashboard/requirements.txt
    python dashboard/load_data.py --csv-dir data --schema-csv-directly

Dry run (prints a plan without loading):
    python dashboard/load_data.py --csv-dir data --dry-run

It expects SUPABASE_DATABASE_URL in the environment (see .env.example).
The loader uses COPY (fast, repeatable) and preserves the raw schema.
"""
import argparse
import csv
import io
import os

import psycopg2
from dotenv import load_dotenv

load_dotenv()

# table name -> (csv filename, ordered column list)
TABLES = {
    "customers": (
        "olist_customers_dataset.csv",
        ["customer_id", "customer_unique_id", "customer_zip_code_prefix",
         "customer_city", "customer_state"],
    ),
    "orders": (
        "olist_orders_dataset.csv",
        ["order_id", "customer_id", "order_status", "order_purchase_timestamp",
         "order_approved_at", "order_delivered_carrier_date",
         "order_delivered_customer_date", "order_estimated_delivery_date"],
    ),
    "products": (
        "olist_products_dataset.csv",
        ["product_id", "product_category_name", "product_name_lenght",
         "product_description_lenght", "product_photos_qty", "product_weight_g",
         "product_length_cm", "product_height_cm", "product_width_cm"],
    ),
    "sellers": (
        "olist_sellers_dataset.csv",
        ["seller_id", "seller_zip_code_prefix", "seller_city", "seller_state"],
    ),
    "order_items": (
        "olist_order_items_dataset.csv",
        ["order_id", "order_item_id", "product_id", "seller_id",
         "shipping_limit_date", "price", "freight_value"],
    ),
    "order_payments": (
        "olist_order_payments_dataset.csv",
        ["order_id", "payment_sequential", "payment_type",
         "payment_installments", "payment_value"],
    ),
    "order_reviews": (
        "olist_order_reviews_dataset.csv",
        ["review_id", "order_id", "review_score", "review_comment_title",
         "review_comment_message", "review_creation_date",
         "review_answer_timestamp"],
    ),
    "geolocation": (
        "olist_geolocation_dataset.csv",
        ["geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng",
         "geolocation_city", "geolocation_state"],
    ),
    "product_category_name_translation": (
        "product_category_name_translation.csv",
        ["product_category_name", "product_category_name_english"],
    ),
}

# Keep original empty strings as NULL (matches the source semantics).
EMPTY_TO_NULL = {
    "order_items": ["shipping_limit_date"],
    "orders": ["order_approved_at", "order_delivered_carrier_date",
               "order_delivered_customer_date", "order_estimated_delivery_date"],
    "order_reviews": ["review_comment_title", "review_comment_message",
                      "review_creation_date", "review_answer_timestamp"],
    "products": ["product_category_name", "product_name_lenght",
                 "product_description_lenght", "product_photos_qty",
                 "product_weight_g", "product_length_cm", "product_height_cm",
                 "product_width_cm"],
}


def copy_batch(cur, table, data_io, columns):
    # COPY is transactional and much faster than row-by-row inserts.
    cur.copy_expert(
        f"COPY {table} ({','.join(columns)}) FROM STDIN WITH (FORMAT csv, NULL '')",
        data_io,
    )


def build_io(csv_path, columns, table):
    out = io.StringIO()
    writer = csv.writer(out, quoting=csv.QUOTE_MINIMAL)
    null_cols = set(EMPTY_TO_NULL.get(table, []))
    with open(csv_path, encoding="utf-8-sig") as fh:  # utf-8-sig strips BOM
        reader = csv.DictReader(fh)
        for row in reader:
            rec = []
            for col in columns:
                val = row.get(col, "")
                if col in null_cols and val == "":
                    rec.append(None)
                else:
                    rec.append(val)
            writer.writerow(rec)
    out.seek(0)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv-dir", default="data")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    db_url = os.environ.get("SUPABASE_DATABASE_URL")
    if not args.dry_run and not db_url:
        raise SystemExit("SUPABASE_DATABASE_URL is not set (see .env.example).")

    plan = []
    for table, (filename, columns) in TABLES.items():
        path = os.path.join(args.csv_dir, filename)
        plan.append((table, path, columns))

    for table, path, columns in plan:
        if not os.path.exists(path):
            print(f"[skip] {table}: {path} not found")
            continue
        data = build_io(path, columns, table)
        if args.dry_run:
            print(f"[plan] {table}: copy from {os.path.basename(path)} ({len(columns)} cols)")
            continue
        with psycopg2.connect(db_url) as conn:
            with conn.cursor() as cur:
                copy_batch(cur, table, data, columns)
        print(f"[ok] {table}: loaded from {os.path.basename(path)}")

    if not args.dry_run:
        print("Done. Run sql/02_data_quality_checks.sql to validate the load.")
        print(f"  Check against: orders 99,441 | payments 103,886 | "
              f"items 112,650 | reviews 99,224 | customers 99,441 | products 32,951")


if __name__ == "__main__":
    main()