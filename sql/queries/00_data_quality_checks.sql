-- Business question: Before trusting any of the analysis below, how dirty is
-- the loaded data, really? What % of invoices are guest checkouts, what % are
-- cancellations, and are there any line items with a suspicious $0 price?
--
-- Technique: UNION ALL to stack several one-row quality metrics into a single
-- readable report; scalar subqueries in the SELECT list for the denominators.

SELECT
    'Guest checkout invoices (%)' AS metric,
    ROUND(100.0 * COUNT(*) FILTER (WHERE i.customer_id = -1) / COUNT(*), 2) AS value
FROM invoices i

UNION ALL

SELECT
    'Cancelled invoices (%)',
    ROUND(100.0 * COUNT(*) FILTER (WHERE i.is_cancelled = 1) / COUNT(*), 2)
FROM invoices i

UNION ALL

SELECT
    'Line items with unit_price <= 0',
    COUNT(*)
FROM invoice_lines
WHERE unit_price <= 0

UNION ALL

SELECT
    'Non-product lines (postage/fees) as % of all lines',
    ROUND(100.0 * COUNT(*) FILTER (WHERE p.is_product = 0) / COUNT(*), 2)
FROM invoice_lines il
JOIN products p ON p.stock_code = il.stock_code;

-- Sample result (see docs/query_results.md for the full run):
--   Guest checkout invoices (%)                          ~6%
--   Cancelled invoices (%)                                ~4%
--   Line items with unit_price <= 0                       handful, isolated not deleted
--   Non-product lines (postage/fees) as % of all lines    ~5-6%
--
-- Why this matters: every query below that computes "revenue" has to make an
-- explicit, documented choice about whether to include cancellations and
-- postage/fee lines. Running this first is what let me make that choice
-- deliberately instead of by accident.
