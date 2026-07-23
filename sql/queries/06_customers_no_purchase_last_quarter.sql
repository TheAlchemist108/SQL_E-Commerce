-- Business question: Which customers bought something earlier in the year
-- but placed NO order in Q4 2023 (Oct-Dec)? This is a lapsed-customer list a
-- retention/win-back email campaign would target.
--
-- Technique: Correlated subquery with NOT EXISTS -- for each customer, check
-- that no row exists in invoices matching them in the Q4 date range.

SELECT
    c.customer_id,
    c.country,
    (SELECT MAX(i2.invoice_date)
     FROM invoices i2
     WHERE i2.customer_id = c.customer_id) AS last_order_date,
    (SELECT ROUND(SUM(il2.line_revenue), 2)
     FROM invoices i2
     JOIN invoice_lines il2 ON il2.invoice_no = i2.invoice_no
     WHERE i2.customer_id = c.customer_id) AS lifetime_revenue
FROM customers c
WHERE c.customer_id <> -1
  AND EXISTS (                                   -- has purchased at some point
      SELECT 1 FROM invoices i
      WHERE i.customer_id = c.customer_id
        AND i.is_cancelled = 0
  )
  AND NOT EXISTS (                                -- but not in Q4 2023
      SELECT 1 FROM invoices i
      WHERE i.customer_id = c.customer_id
        AND i.is_cancelled = 0
        AND i.invoice_date >= '2023-10-01'
        AND i.invoice_date <  '2024-01-01'
  )
ORDER BY lifetime_revenue DESC
LIMIT 25;
