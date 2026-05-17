"""
Reads all 11 CSVs from the data/ folder and loads them
into your PostgreSQL database one table at a time.

HOW TO RUN:
    python scripts/load_to_postgres.py

BEFORE YOU RUN:
    1. createdb retaillens             (creates the empty database)
    2. psql -d retaillens -f sql/schema.sql   (creates the tables)
    3. pip install -r requirements.txt        (installs libraries)
    4. Fill in your credentials in .env       (see .env.example)
"""

import os
import time
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv


# =============================================================
# STEP 1: Load credentials from the .env file
# =============================================================
# load_dotenv() reads your .env file and makes those values
# available via os.getenv(). This way your password never
# appears directly in code.
load_dotenv()

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASSWORD")


# =============================================================
# STEP 2: Define where the CSVs live
# =============================================================
# os.path.dirname(__file__) = the folder this script lives in (scripts/)
# ".." goes one level up to the project root
# Then we go into data/
DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")


# =============================================================
# STEP 3: Define load order
# =============================================================
# Order matters because of FOREIGN KEYS.
# Example: order_items references orders and sellers.
# So orders and sellers must be loaded BEFORE order_items.
# If you load in the wrong order, Postgres will throw an error.
#
# Format: (csv filename without .csv, table name, date columns to parse)
# parse_dates tells pandas which columns contain timestamps
# so it reads them as datetime objects instead of plain strings.
# =============================================================
LOAD_ORDER = [
    ("olist_customers_dataset",                  "customers",            []),
    ("olist_sellers_dataset",                    "sellers",              []),
    ("olist_products_dataset",                   "products",             []),
    ("product_category_name_translation",        "category_translation", []),
    ("olist_geolocation_dataset",          "geolocation",          []),
    ("olist_orders_dataset",                     "orders",               [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ]),
    ("olist_order_items_dataset",                "order_items",          ["shipping_limit_date"]),
    ("olist_order_payments_dataset",             "order_payments",       []),
    ("olist_order_reviews_dataset",              "order_reviews",        [
        "review_creation_date",
        "review_answer_timestamp",
    ]),
    ("olist_marketing_qualified_leads_dataset",  "mql",                  ["first_contact_date"]),
    ("olist_closed_deals_dataset",               "closed_deals",         ["won_date"]),
]


# =============================================================
# STEP 4: Create the database engine
# =============================================================
# The "engine" is SQLAlchemy's way of managing the connection
# to Postgres. Think of it as the phone line between Python
# and your database.
#
# The connection string format is:
#   dialect+driver://user:password@host:port/database
# =============================================================
def make_engine():
    connection_string = (
        f"postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    )
    return create_engine(connection_string)


# =============================================================
# STEP 5: Load one CSV into one table
# =============================================================
def load_table(engine, csv_path, table_name, parse_dates):
    # Read the CSV into a pandas DataFrame
    df = pd.read_csv(csv_path, parse_dates=parse_dates, low_memory=False)

    # Strip accidental whitespace from text columns.
    # CSVs often have " value " instead of "value".
    str_cols = df.select_dtypes(include=["str"]).columns
    for col in str_cols:
        df[col] = df[col].str.strip()

    # Write to Postgres.
    # if_exists="append" means: the table already exists (schema.sql created it),
    # just add rows to it. Don't recreate the table.
    # method="multi" sends multiple rows per INSERT — much faster than one-by-one.
    # chunksize=4500 sends 4500 rows at a time to avoid memory issues.
    df.to_sql(
        name=table_name,
        con=engine,
        if_exists="append",
        index=False,
        method="multi",
        chunksize=4500,
    )
    return len(df)


# =============================================================
# STEP 6: Main — connect, load each table, report results
# =============================================================
def main():
    engine = make_engine()

    # Test the connection before doing anything.
    # If this fails, it tells you exactly what to check.
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print(f"Connected to PostgreSQL — database: {DB_NAME}\n")
    except Exception as e:
        print(f"Could not connect: {e}")
        print("\nThings to check:")
        print("  Is Postgres running?  →  pg_ctl status")
        print("  Did you create the DB?  →  createdb retaillens")
        print("  Is your password correct in .env?")
        return  # Stop here — no point continuing if connection failed

    # Load each table in the defined order
    total_rows = 0
    for csv_stem, table_name, parse_dates in LOAD_ORDER:
        csv_path = os.path.join(DATA_DIR, csv_stem + ".csv")

        if not os.path.exists(csv_path):
            print(f"  NOT FOUND — skipping: {csv_path}")
            continue

        t0 = time.time()
        try:
            rows = load_table(engine, csv_path, table_name, parse_dates)
            elapsed = round(time.time() - t0, 1)
            print(f"  {table_name:<30}  {rows:>8,} rows  ({elapsed}s)")
            total_rows += rows
        except Exception as e:
            print(f"  FAILED — {table_name}: {e}")
            if hasattr(e, '__cause__') and e.__cause__:
                print(f"  Root cause: {e.__cause__}")
            if hasattr(e, 'orig') and e.orig:
                print(f"  Postgres error: {e.orig}")
            print("  → Did you run schema.sql first?")

    print(f"\nDone. {total_rows:,} total rows loaded into '{DB_NAME}'.")
    engine.dispose()  # cleanly close all connections


if __name__ == "__main__":
    main()