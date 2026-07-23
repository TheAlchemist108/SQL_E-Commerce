"""
generate_data.py
-----------------
Generates data/raw_online_retail.csv — a single flat, denormalized export that
mimics what you'd actually get from an e-commerce order system: one row per
invoice line item, with customer and product attributes repeated on every row.

This is a synthetic dataset, built with Python's standard library only (no
external download), but its shape and its data-quality problems are modeled
directly on the well-known UCI "Online Retail II" dataset (a UK-based online
gift retailer, Dec 2009-Dec 2011) — the de facto standard practice dataset for
SQL/ETL portfolio projects. See README.md "About the data" for why a generator
was used instead of bundling the original file.

Intentional messiness injected (documented, not accidental):
  1. ~6% of rows have a missing CustomerID  -> guest checkouts
  2. Cancellations are separate invoices whose InvoiceNo is prefixed with 'C'
     and whose Quantity is negative (mirrors the real dataset's convention)
  3. Non-product "StockCode" rows for postage/fees (POST, DOT, M, BANK CHARGES,
     AMAZONFEE) mixed in with real product rows
  4. The same StockCode sometimes has inconsistent Description casing/whitespace
     across rows (simulates manual re-entry / different warehouse staff)
  5. Country values are inconsistently formatted ("United Kingdom" vs "UK" vs
     "  united kingdom") for a subset of rows
  6. A handful of exact duplicate rows (double-submitted order lines)
  7. A handful of UnitPrice <= 0 rows (data entry errors / free samples)
  8. Whitespace-padded InvoiceNo / StockCode on a subset of rows
"""

import csv
import random
from datetime import datetime, timedelta

random.seed(42)  # reproducible output

OUT_PATH = "data/raw_online_retail.csv"

COUNTRIES = [
    "United Kingdom", "Germany", "France", "Ireland", "Spain",
    "Netherlands", "Belgium", "Portugal", "Italy", "Australia",
]
COUNTRY_VARIANTS = {
    "United Kingdom": ["United Kingdom", "UK", "  united kingdom", "U.K."],
}

FIRST_NAMES = ["Olivia","Liam","Emma","Noah","Ava","Oliver","Sophia","Elijah","Isabella","James",
               "Mia","William","Amelia","Benjamin","Charlotte","Lucas","Harper","Henry","Evelyn","Alex",
               "Grace","Jack","Chloe","Leo","Ella","Mason","Aria","Ethan","Zoe","Daniel"]
LAST_NAMES = ["Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis","Rodriguez","Martinez",
              "Wilson","Anderson","Taylor","Thomas","Moore","Jackson","Martin","Lee","Perez","Thompson",
              "White","Harris","Clark","Lewis","Walker","Hall","Allen","Young","King","Wright"]

# (StockCode, Description, base UnitPrice)
PRODUCTS = [
    ("85123A", "WHITE HANGING HEART T-LIGHT HOLDER", 2.55),
    ("71053",  "WHITE METAL LANTERN", 3.39),
    ("84406B", "CREAM CUPID HEARTS COAT HANGER", 2.75),
    ("84029G", "KNITTED UNION FLAG HOT WATER BOTTLE", 3.75),
    ("84029E", "RED WOOLLY HOTTIE WHITE HEART", 3.75),
    ("22752",  "SET 7 BABUSHKA NESTING BOXES", 7.65),
    ("21730",  "GLASS STAR FROSTED T-LIGHT HOLDER", 4.25),
    ("22633",  "HAND WARMER UNION JACK", 1.85),
    ("22632",  "HAND WARMER RED POLKA DOT", 1.85),
    ("84879",  "ASSORTED COLOUR BIRD ORNAMENT", 1.69),
    ("22745",  "POPPY'S PLAYHOUSE BEDROOM", 2.10),
    ("22748",  "POPPY'S PLAYHOUSE KITCHEN", 2.10),
    ("22749",  "FELTCRAFT PRINCESS CHARLOTTE DOLL", 3.75),
    ("22625",  "RED KITCHEN SCALES", 8.50),
    ("22622",  "BOX OF VINTAGE ALPHABET BLOCKS", 9.95),
    ("21212",  "PACK OF 72 RETROSPOT CAKE CASES", 0.55),
    ("20725",  "LUNCH BAG RED RETROSPOT", 1.65),
    ("20727",  "LUNCH BAG BLACK SKULL", 1.65),
    ("20728",  "LUNCH BAG CARS BLUE", 1.65),
    ("21931",  "JUMBO STORAGE BAG SUKI", 2.08),
    ("21929",  "JUMBO BAG PINK POLKADOT", 2.08),
    ("23203",  "JUMBO BAG DOILY PATTERNS", 2.08),
    ("22423",  "REGENCY CAKESTAND 3 TIER", 12.75),
    ("47566",  "PARTY BUNTING", 4.95),
    ("21777",  "RECIPE BOX WITH METAL HEART", 5.95),
    ("84991",  "60 TEATIME FAIRY CAKE CASES", 0.85),
    ("22960",  "JAM MAKING SET WITH JARS", 4.25),
    ("23298",  "SPACEBOY LUNCH BOX", 1.95),
    ("23355",  "HOT WATER BOTTLE KEEP CALM", 3.95),
    ("22111",  "SCOTTIE DOG HOT WATER BOTTLE", 4.95),
    ("21754",  "HOME BUILDING BLOCK WORD", 5.95),
    ("21755",  "LOVE BUILDING BLOCK WORD", 5.95),
    ("23245",  "SET OF 3 REGENCY CAKE TINS", 4.95),
    ("22197",  "SMALL POPCORN HOLDER", 0.85),
    ("21471",  "TRAVEL CARD WALLET SKULL", 0.42),
]

# Non-product adjustment codes that appear on real invoices (not "products")
NON_PRODUCT_CODES = [
    ("POST", "POSTAGE", 18.00),
    ("DOT", "DOTCOM POSTAGE", 15.00),
    ("M", "MANUAL", 5.00),
    ("BANK CHARGES", "BANK CHARGES", 15.00),
    ("AMAZONFEE", "AMAZON FEE", 12.50),
]

N_CUSTOMERS = 350
N_INVOICES = 1400
START_DATE = datetime(2023, 1, 1)
END_DATE = datetime(2023, 12, 31)

def random_date():
    # weight toward Nov/Dec (seasonality)
    if random.random() < 0.25:
        month = random.choice([11, 12])
        day = random.randint(1, 28)
        base = datetime(2023, month, day)
    else:
        span = (END_DATE - START_DATE).days
        base = START_DATE + timedelta(days=random.randint(0, span))
    return base.replace(hour=random.randint(8, 19), minute=random.randint(0, 59))

def build_customers():
    customers = []
    for i in range(N_CUSTOMERS):
        cust_id = 12000 + i
        name = f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"
        country = random.choices(COUNTRIES, weights=[55,8,8,6,5,5,4,3,3,3])[0]
        customers.append({"CustomerID": cust_id, "Name": name, "Country": country})
    return customers

def messy_country(country):
    variants = COUNTRY_VARIANTS.get(country)
    if variants and random.random() < 0.15:
        return random.choice(variants)
    return country

def messy_description(desc):
    r = random.random()
    if r < 0.08:
        return desc.lower()
    if r < 0.14:
        return f"  {desc.title()}  "
    return desc

def main():
    customers = build_customers()
    rows = []
    invoice_no = 536365

    for _ in range(N_INVOICES):
        invoice_no += random.randint(1, 3)
        cust = random.choice(customers)
        # ~6% guest checkout: no CustomerID
        cust_id = "" if random.random() < 0.06 else cust["CustomerID"]
        country = messy_country(cust["Country"])
        inv_date = random_date()
        is_cancellation = random.random() < 0.04
        inv_str = f"C{invoice_no}" if is_cancellation else str(invoice_no)

        n_lines = random.randint(1, 10)
        chosen_products = random.sample(PRODUCTS, k=min(n_lines, len(PRODUCTS)))

        for stock_code, desc, base_price in chosen_products:
            qty = random.randint(1, 24)
            if is_cancellation:
                qty = -abs(qty)
            price = round(base_price * random.uniform(0.9, 1.15), 2)
            # rare data entry error: zero/negative price
            if random.random() < 0.01:
                price = 0.0
            sc = stock_code
            if random.random() < 0.03:
                sc = f" {sc} "  # stray whitespace
            rows.append([inv_str, sc, messy_description(desc), qty,
                         inv_date.strftime("%m/%d/%Y %H:%M"), price, cust_id, country])

        # occasionally add a postage/fee line to the same invoice
        if not is_cancellation and random.random() < 0.35:
            code, desc, price = random.choice(NON_PRODUCT_CODES)
            rows.append([inv_str, code, desc, 1,
                         inv_date.strftime("%m/%d/%Y %H:%M"), price, cust_id, country])

    # inject a handful of exact duplicate rows (double-submitted lines)
    for _ in range(25):
        rows.append(random.choice(rows).copy())

    random.shuffle(rows)

    with open(OUT_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["InvoiceNo", "StockCode", "Description", "Quantity",
                          "InvoiceDate", "UnitPrice", "CustomerID", "Country"])
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {OUT_PATH}")

if __name__ == "__main__":
    main()
