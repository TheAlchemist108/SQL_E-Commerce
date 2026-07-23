-- Business question: Which individual orders were unusually large FOR THAT
-- CUSTOMER (i.e. more than 2x their own average order value)? Useful for
-- flagging potential bulk/wholesale buyers, gifting spikes, or, on the flip
-- side, data-entry errors worth a manual review.
--
-- Technique: Correlated subquery in the WHERE clause -- the threshold
-- ("2x this customer's average order value") is computed per-customer, not
-- globally, so it has to be re-evaluated for each row against that same
-- customer's own history.

SELECT
    i.invoice_no,
    i.customer_id,
    i.invoice_date,
    ROUND(SUM(il.line_revenue), 2) AS order_value
FROM invoices i
JOIN invoice_lines il ON il.invoice_no = i.invoice_no
WHERE i.is_cancelled = 0
  AND i.customer_id <> -1
GROUP BY i.invoice_no, i.customer_id, i.invoice_date
HAVING SUM(il.line_revenue) > 2 * (
    -- this customer's own average order value, computed independently
    SELECT AVG(order_total)
    FROM (
        SELECT SUM(il2.line_revenue) AS order_total
        FROM invoices i2
        JOIN invoice_lines il2 ON il2.invoice_no = i2.invoice_no
        WHERE i2.customer_id = i.customer_id
          AND i2.is_cancelled = 0
        GROUP BY i2.invoice_no
    )
)
ORDER BY order_value DESC
LIMIT 25;
