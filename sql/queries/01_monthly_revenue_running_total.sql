-- Business question: What's our month-by-month net revenue trend for 2023,
-- and what's the cumulative (running total) revenue through each month?
--
-- Technique: CTE to pre-aggregate by month, then a window function
-- (SUM() OVER ... ORDER BY month) to compute a running total without a
-- self-join. Product sales only (postage/fees excluded); cancellations
-- (negative quantity) are included so the number reflects real net revenue.

WITH monthly AS (
    SELECT
        strftime('%Y-%m', i.invoice_date) AS month,
        ROUND(SUM(il.line_revenue), 2)     AS monthly_revenue
    FROM invoice_lines il
    JOIN invoices i  ON i.invoice_no = il.invoice_no
    JOIN products p  ON p.stock_code = il.stock_code
    WHERE p.is_product = 1
    GROUP BY month
)
SELECT
    month,
    monthly_revenue,
    ROUND(SUM(monthly_revenue) OVER (ORDER BY month), 2) AS running_total_revenue
FROM monthly
ORDER BY month;
