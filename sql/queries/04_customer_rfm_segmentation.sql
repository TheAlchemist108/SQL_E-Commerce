-- Business question: Which customers are our best ("Champions"), which are
-- "At Risk" of churning, and which are basically inactive? This is a classic
-- RFM (Recency, Frequency, Monetary) segmentation used to target retention
-- campaigns and VIP treatment.
--
-- Technique: CTE to compute R/F/M per customer, window functions (NTILE) to
-- score each dimension into quintiles relative to the rest of the customer
-- base, then CASE to translate the 3 scores into a human-readable segment.

WITH customer_orders AS (
    SELECT
        c.customer_id,
        c.country,
        MAX(i.invoice_date)               AS last_order_date,
        COUNT(DISTINCT i.invoice_no)       AS frequency,
        ROUND(SUM(il.line_revenue), 2)     AS monetary
    FROM customers c
    JOIN invoices i       ON i.customer_id = c.customer_id AND i.is_cancelled = 0
    JOIN invoice_lines il ON il.invoice_no = i.invoice_no
    JOIN products p       ON p.stock_code = il.stock_code AND p.is_product = 1
    WHERE c.customer_id <> -1                 -- exclude the guest bucket; RFM needs a real identity
    GROUP BY c.customer_id, c.country
),
scored AS (
    SELECT
        customer_id,
        country,
        last_order_date,
        frequency,
        monetary,
        -- recency: days between last order and the most recent date in the dataset
        CAST(julianday((SELECT MAX(invoice_date) FROM invoices)) - julianday(last_order_date) AS INT) AS days_since_last_order,
        NTILE(5) OVER (ORDER BY julianday(last_order_date) DESC) AS recency_score,   -- 5 = most recent
        NTILE(5) OVER (ORDER BY frequency ASC)                    AS frequency_score,
        NTILE(5) OVER (ORDER BY monetary ASC)                     AS monetary_score
    FROM customer_orders
)
SELECT
    customer_id,
    country,
    days_since_last_order,
    frequency,
    monetary,
    recency_score,
    frequency_score,
    monetary_score,
    CASE
        WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4 THEN 'Champion'
        WHEN recency_score >= 4 AND frequency_score <= 2 THEN 'New / Promising'
        WHEN recency_score <= 2 AND frequency_score >= 4 THEN 'At Risk (was loyal)'
        WHEN recency_score <= 2 AND frequency_score <= 2 THEN 'Lost / Inactive'
        ELSE 'Regular'
    END AS rfm_segment
FROM scored
ORDER BY monetary DESC
LIMIT 25;
