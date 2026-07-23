-- Business question: Which months grew and which months shrank vs. the prior
-- month, and by how much (%)?
--
-- Technique: CTE for monthly revenue, then LAG() to pull the previous row's
-- value into the current row without a self-join.

WITH monthly AS (
    SELECT
        strftime('%Y-%m', i.invoice_date) AS month,
        ROUND(SUM(il.line_revenue), 2)     AS monthly_revenue
    FROM invoice_lines il
    JOIN invoices i  ON i.invoice_no = il.invoice_no
    JOIN products p  ON p.stock_code = il.stock_code
    WHERE p.is_product = 1
    GROUP BY month
),
with_prior AS (
    SELECT
        month,
        monthly_revenue,
        LAG(monthly_revenue) OVER (ORDER BY month) AS prior_month_revenue
    FROM monthly
)
SELECT
    month,
    monthly_revenue,
    prior_month_revenue,
    CASE
        WHEN prior_month_revenue IS NULL OR prior_month_revenue = 0 THEN NULL
        ELSE ROUND(100.0 * (monthly_revenue - prior_month_revenue) / prior_month_revenue, 1)
    END AS mom_growth_pct
FROM with_prior
ORDER BY month;
