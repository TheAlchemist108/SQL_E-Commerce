-- Business question: What's the #1 and #2 best-selling product (by revenue)
-- in each of our top countries? Useful for regional merchandising decisions.
--
-- Technique: JOIN across all 4 tables, CTE to pre-aggregate revenue per
-- (country, product), then RANK() PARTITION BY country to rank products
-- within each country independently.

WITH country_product_revenue AS (
    SELECT
        c.country,
        p.stock_code,
        p.description,
        ROUND(SUM(il.line_revenue), 2) AS revenue
    FROM invoice_lines il
    JOIN invoices i   ON i.invoice_no = il.invoice_no
    JOIN customers c  ON c.customer_id = i.customer_id
    JOIN products p   ON p.stock_code = il.stock_code
    WHERE p.is_product = 1
      AND i.is_cancelled = 0
    GROUP BY c.country, p.stock_code, p.description
),
ranked AS (
    SELECT
        country,
        description,
        revenue,
        RANK() OVER (PARTITION BY country ORDER BY revenue DESC) AS rank_in_country
    FROM country_product_revenue
)
SELECT country, rank_in_country, description, revenue
FROM ranked
WHERE rank_in_country <= 2
  AND country IN (
      -- limit to the top 5 countries by total customer count, via subquery
      SELECT country FROM customers
      GROUP BY country
      ORDER BY COUNT(*) DESC
      LIMIT 5
  )
ORDER BY country, rank_in_country;
