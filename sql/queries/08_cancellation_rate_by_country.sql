-- Business question: Does cancellation/return rate vary meaningfully by
-- country? If one market cancels far more than others, that's worth
-- investigating (shipping issues, product-market fit, fraud, etc.).
--
-- Technique: JOIN + conditional aggregation (COUNT ... FILTER) to compute a
-- rate in a single pass, plus a scalar subquery to add the overall/global
-- rate as a benchmark column on every row.

SELECT
    c.country,
    COUNT(DISTINCT i.invoice_no) AS total_invoices,
    COUNT(DISTINCT i.invoice_no) FILTER (WHERE i.is_cancelled = 1) AS cancelled_invoices,
    ROUND(
        100.0 * COUNT(DISTINCT i.invoice_no) FILTER (WHERE i.is_cancelled = 1)
        / COUNT(DISTINCT i.invoice_no), 1
    ) AS cancellation_rate_pct,
    (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE is_cancelled = 1) / COUNT(*), 1)
     FROM invoices) AS overall_cancellation_rate_pct
FROM invoices i
JOIN customers c ON c.customer_id = i.customer_id
GROUP BY c.country
HAVING COUNT(DISTINCT i.invoice_no) >= 10   -- ignore countries with too few orders to be meaningful
ORDER BY cancellation_rate_pct DESC;
