-- schema.sql
-- Normalized schema for the online retail dataset.
--
-- The raw export (data/raw_online_retail.csv) is a single flat file: one row
-- per invoice line, with customer and product attributes repeated on every
-- row. That's fine for a spreadsheet but it's not queryable at scale and it
-- can't enforce that "customer 12009" always means the same person. So we
-- normalize it into four tables:
--
--   customers      one row per real customer (CustomerID is nullable in the
--                   source for guest checkouts, so guest orders point at a
--                   synthetic customer_id = -1 "GUEST" row instead of NULL)
--   products       one row per StockCode, with ONE canonical description
--                   (the raw file has inconsistent casing/whitespace for the
--                   same StockCode across rows -- we pick the most frequent
--                   cleaned description per code)
--   invoices       one row per InvoiceNo (order/cancellation header)
--   invoice_lines  one row per line item, FK to invoices and products
--
-- This mirrors how a real OLTP e-commerce schema is shaped, and is what lets
-- us write joins/subqueries/window functions instead of just grouping a flat
-- table.

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS invoice_lines;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id   INTEGER PRIMARY KEY,   -- -1 reserved for guest checkouts
    country        TEXT NOT NULL
);

CREATE TABLE products (
    stock_code     TEXT PRIMARY KEY,
    description    TEXT NOT NULL,
    is_product     INTEGER NOT NULL DEFAULT 1,  -- 0 for postage/fee/manual codes
    unit_price_avg REAL                          -- reference price, informational only
);

CREATE TABLE invoices (
    invoice_no     TEXT PRIMARY KEY,
    customer_id    INTEGER NOT NULL REFERENCES customers(customer_id),
    invoice_date   TEXT NOT NULL,        -- ISO 8601 'YYYY-MM-DD HH:MM'
    is_cancelled   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE invoice_lines (
    invoice_line_id INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_no      TEXT NOT NULL REFERENCES invoices(invoice_no),
    stock_code      TEXT NOT NULL REFERENCES products(stock_code),
    quantity        INTEGER NOT NULL,
    unit_price      REAL NOT NULL,
    line_revenue    REAL NOT NULL         -- quantity * unit_price, pre-computed
);

CREATE INDEX idx_invoices_customer   ON invoices(customer_id);
CREATE INDEX idx_invoices_date       ON invoices(invoice_date);
CREATE INDEX idx_lines_invoice       ON invoice_lines(invoice_no);
CREATE INDEX idx_lines_product       ON invoice_lines(stock_code);
