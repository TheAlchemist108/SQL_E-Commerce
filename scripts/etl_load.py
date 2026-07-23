"""
etl_load.py
-----------
Cleans data/raw_online_retail.csv and loads it into data/ecommerce.db
(SQLite) according to sql/schema/schema.sql.

Cleaning rules applied (each one addresses a specific issue in the raw file
-- see README.md "Data cleaning decisions" for the reasoning behind each):

 1. Strip whitespace from InvoiceNo / StockCode / Description / Country.
 2. Normalize Country to a canonical value via a lookup of known variants
    ("UK", "U.K.", "  united kingdom" -> "United Kingdom").
 3. Missing CustomerID -> mapped to a synthetic guest customer_id = -1,
    instead of being dropped or left NULL, so guest orders still aggregate
    correctly (e.g. "revenue by customer" doesn't silently lose guest sales).
 4. Cancellations: InvoiceNo starting with 'C' -> invoices.is_cancelled = 1.
    Their negative quantities are kept as-is (they represent real returns);
    it's a query-time decision whether to net them against sales.
 5. Products: each StockCode may have several differently-formatted
    Description strings in the raw file. We pick the mode (most frequent)
    cleaned description as the canonical one, so `products` has exactly one
    row per StockCode.
 6. Non-product codes (POST, DOT, M, BANK CHARGES, AMAZONFEE) are kept as
    real rows in `products` but flagged is_product = 0, so revenue queries
    can choose to include or exclude postage/fees explicitly.
 7. Rows with unit_price <= 0 are kept (they're real, if rare, in this kind
    of export) but are easy to isolate for a data-quality query since
    line_revenue will be 0 or negative -- see queries/00_data_quality_checks.sql.
 8. Exact duplicate rows (same invoice/product/qty/price/customer/date) are
    de-duplicated before loading, since they're double-submitted line items,
    not genuinely repeated purchases.
 9. InvoiceDate parsed from "MM/DD/YYYY HH:MM" into ISO "YYYY-MM-DD HH:MM"
    so date sorting/filtering works correctly in SQL (string-sortable).
"""

import csv
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime

import os
import shutil

RAW_CSV = "data/raw_online_retail.csv"
DB_PATH = "data/ecommerce.db"
TMP_DB_PATH = "/tmp/ecommerce_build.db"
SCHEMA_PATH = "sql/schema/schema.sql"

COUNTRY_CANON = {
    "united kingdom": "United Kingdom",
    "uk": "United Kingdom",
    "u.k.": "United Kingdom",
}

GUEST_ID = -1


def clean_country(raw):
    c = raw.strip()
    canon = COUNTRY_CANON.get(c.lower())
    return canon if canon else c


def clean_description(raw):
    return " ".join(raw.strip().split()).upper()


def load_raw_rows():
    with open(RAW_CSV, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main():
    raw_rows = load_raw_rows()
    print(f"Read {len(raw_rows)} raw rows")

    # de-dup exact duplicate rows
    seen = set()
    rows = []
    dup_count = 0
    for r in raw_rows:
        key = tuple(r[k] for k in r)
        if key in seen:
            dup_count += 1
            continue
        seen.add(key)
        rows.append(r)
    print(f"Dropped {dup_count} exact-duplicate rows")

    customers = {}          # customer_id -> country
    product_desc_votes = defaultdict(Counter)   # stock_code -> Counter(description)
    product_prices = defaultdict(list)          # stock_code -> [unit_price,...]
    non_product_codes = {"POST", "DOT", "M", "BANK CHARGES", "AMAZONFEE"}

    invoices = {}            # invoice_no -> (customer_id, date_iso, is_cancelled)
    lines = []                # list of (invoice_no, stock_code, qty, price, revenue)

    bad_price_rows = 0

    for r in rows:
        invoice_no = r["InvoiceNo"].strip()
        stock_code = r["StockCode"].strip().upper()
        description = clean_description(r["Description"])
        quantity = int(r["Quantity"])
        unit_price = float(r["UnitPrice"])
        raw_cust = r["CustomerID"].strip()
        country = clean_country(r["Country"])

        customer_id = int(raw_cust) if raw_cust else GUEST_ID
        customers.setdefault(customer_id, country)

        is_cancelled = 1 if invoice_no.upper().startswith("C") else 0
        invoice_dt = datetime.strptime(r["InvoiceDate"].strip(), "%m/%d/%Y %H:%M")
        invoice_iso = invoice_dt.strftime("%Y-%m-%d %H:%M")

        invoices.setdefault(invoice_no, (customer_id, invoice_iso, is_cancelled))

        product_desc_votes[stock_code][description] += 1
        if unit_price > 0:
            product_prices[stock_code].append(unit_price)
        else:
            bad_price_rows += 1

        line_revenue = round(quantity * unit_price, 2)
        lines.append((invoice_no, stock_code, quantity, unit_price, line_revenue))

    print(f"Rows with unit_price <= 0: {bad_price_rows} (kept, flagged via line_revenue)")
    print(f"Unique customers (incl. guest bucket): {len(customers)}")
    print(f"Unique products/codes: {len(product_desc_votes)}")
    print(f"Unique invoices: {len(invoices)}")

    # build db
    with open(SCHEMA_PATH) as f:
        schema_sql = f.read()

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(schema_sql)

    conn.executemany(
        "INSERT INTO customers (customer_id, country) VALUES (?, ?)",
        list(customers.items()),
    )

    product_rows = []
    for code, votes in product_desc_votes.items():
        canonical_desc = votes.most_common(1)[0][0]
        prices = product_prices.get(code, [])
        avg_price = round(sum(prices) / len(prices), 2) if prices else None
        is_product = 0 if code in non_product_codes else 1
        product_rows.append((code, canonical_desc, is_product, avg_price))
    conn.executemany(
        "INSERT INTO products (stock_code, description, is_product, unit_price_avg) "
        "VALUES (?, ?, ?, ?)",
        product_rows,
    )

    conn.executemany(
        "INSERT INTO invoices (invoice_no, customer_id, invoice_date, is_cancelled) "
        "VALUES (?, ?, ?, ?)",
        [(no, cust, dt, canc) for no, (cust, dt, canc) in invoices.items()],
    )

    conn.executemany(
        "INSERT INTO invoice_lines (invoice_no, stock_code, quantity, unit_price, line_revenue) "
        "VALUES (?, ?, ?, ?, ?)",
        lines,
    )

    conn.commit()

    # sanity check counts
    for table in ["customers", "products", "invoices", "invoice_lines"]:
        n = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"{table}: {n} rows loaded")

    conn.close()
    print(f"\nDone. Database written to {DB_PATH}")


if __name__ == "__main__":
    main()
