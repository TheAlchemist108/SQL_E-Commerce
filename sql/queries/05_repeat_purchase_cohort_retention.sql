-- Business question: Of the customers who made their first purchase in a
-- given month (a "cohort"), what % came back and bought again in a later
-- month? This is the standard cohort-retention view used to judge whether
-- marketing spend is producing loyal customers or one-time buyers.
--
-- Technique: CTE to find each customer's first-purchase month (via
-- MIN() as a window/aggregate), self-referencing JOIN between the cohort
-- table and the orders table to find repeat activity, then conditional
-- aggregation to build a simple retention matrix.

WITH first_purchase AS (
    SELECT
        i.customer_id,
        MIN(strftime('%Y-%m', i.invoice_date)) AS cohort_month
    FROM invoices i
    WHERE i.is_cancelled = 0
      AND i.customer_id <> -1
    GROUP BY i.customer_id
),
orders_with_cohort AS (
    SELECT
        fp.customer_id,
        fp.cohort_month,
        strftime('%Y-%m', i.invoice_date) AS order_month
    FROM first_purchase fp
    JOIN invoices i
        ON i.customer_id = fp.customer_id
       AND i.is_cancelled = 0
),
cohort_activity AS (
    SELECT DISTINCT
        customer_id,
        cohort_month,
        order_month,
        -- months since first purchase, as an integer offset
        (CAST(substr(order_month, 1, 4) AS INT) - CAST(substr(cohort_month, 1, 4) AS INT)) * 12
            + (CAST(substr(order_month, 6, 2) AS INT) - CAST(substr(cohort_month, 6, 2) AS INT)) AS month_offset
    FROM orders_with_cohort
)
SELECT
    cohort_month,
    COUNT(DISTINCT customer_id) AS cohort_size,
    COUNT(DISTINCT CASE WHEN month_offset = 1 THEN customer_id END) AS active_month_1,
    COUNT(DISTINCT CASE WHEN month_offset = 2 THEN customer_id END) AS active_month_2,
    COUNT(DISTINCT CASE WHEN month_offset = 3 THEN customer_id END) AS active_month_3,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_offset = 1 THEN customer_id END)
          / COUNT(DISTINCT customer_id), 1) AS retained_month_1_pct
FROM cohort_activity
GROUP BY cohort_month
ORDER BY cohort_month;
