-- =============================================================
-- 03_analysis.sql  |  NovaCart
-- Answers the management questions using the clean tables.
-- Run one query at a time: select (highlight) the query, then press F5.
-- Only the highlighted text runs.
-- =============================================================


-- Q1. Monthly P&L: is NovaCart profitable, and how did profit change month by month?
WITH sales AS (
    SELECT SUBSTR(o.order_date, 1, 7)                          AS month,
           SUM(i.quantity * i.unit_price)                      AS gross_sales,
           SUM(i.quantity * i.unit_price * (1 - o.discount_pct)) AS net_sales,
           SUM(i.quantity * p.unit_cost)                       AS cogs
    FROM order_items AS i
    JOIN orders   AS o ON o.order_id   = i.order_id
    JOIN products AS p ON p.product_id = i.product_id
    WHERE o.status = 'Delivered'
    GROUP BY month
),
refunds AS (
    SELECT SUBSTR(o.order_date, 1, 7) AS month,
           SUM(r.refund_amount)       AS refunds
    FROM returns AS r
    JOIN order_items AS i ON i.order_item_id = r.order_item_id
    JOIN orders      AS o ON o.order_id      = i.order_id
    WHERE o.status = 'Delivered'
    GROUP BY month
),
shipping AS (
    SELECT SUBSTR(order_date, 1, 7) AS month,
           SUM(shipping_cost)       AS shipping
    FROM orders
    WHERE status = 'Delivered'
    GROUP BY month
),
marketing AS (
    SELECT month, SUM(spend_usd) AS marketing
    FROM marketing_spend
    GROUP BY month
),
pnl AS (
    SELECT s.month,
           s.gross_sales,
           s.net_sales,
           COALESCE(r.refunds, 0)                                  AS refunds,
           s.net_sales - COALESCE(r.refunds, 0)                    AS net_revenue,
           s.cogs,
           s.net_sales - COALESCE(r.refunds, 0) - s.cogs           AS gross_profit,
           sh.shipping,
           m.marketing
    FROM sales AS s
    LEFT JOIN refunds   AS r  ON r.month  = s.month
    LEFT JOIN shipping  AS sh ON sh.month = s.month
    LEFT JOIN marketing AS m  ON m.month  = s.month
)
SELECT month,
       ROUND(net_revenue, 0)                                        AS net_revenue,
       ROUND(gross_profit, 0)                                       AS gross_profit,
       ROUND(100.0 * gross_profit / net_revenue, 1)                 AS gross_margin_pct,
       ROUND(marketing, 0)                                          AS marketing,
       ROUND(gross_profit - shipping - marketing, 0)                AS operating_profit,
       ROUND(100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY month))
             / LAG(net_revenue) OVER (ORDER BY month), 1)           AS revenue_growth_pct
FROM pnl
ORDER BY month;


-- Q1b. Total P&L for all 18 months (same CTEs, different final SELECT)
WITH sales AS (
    SELECT SUBSTR(o.order_date, 1, 7)                          AS month,
           SUM(i.quantity * i.unit_price)                      AS gross_sales,
           SUM(i.quantity * i.unit_price * (1 - o.discount_pct)) AS net_sales,
           SUM(i.quantity * p.unit_cost)                       AS cogs
    FROM order_items AS i
    JOIN orders   AS o ON o.order_id   = i.order_id
    JOIN products AS p ON p.product_id = i.product_id
    WHERE o.status = 'Delivered'
    GROUP BY month
),
refunds AS (
    SELECT SUBSTR(o.order_date, 1, 7) AS month,
           SUM(r.refund_amount)       AS refunds
    FROM returns AS r
    JOIN order_items AS i ON i.order_item_id = r.order_item_id
    JOIN orders      AS o ON o.order_id      = i.order_id
    WHERE o.status = 'Delivered'
    GROUP BY month
),
shipping AS (
    SELECT SUBSTR(order_date, 1, 7) AS month,
           SUM(shipping_cost)       AS shipping
    FROM orders
    WHERE status = 'Delivered'
    GROUP BY month
),
marketing AS (
    SELECT month, SUM(spend_usd) AS marketing
    FROM marketing_spend
    GROUP BY month
),
pnl AS (
    SELECT s.month,
           s.gross_sales,
           s.net_sales,
           COALESCE(r.refunds, 0)                                  AS refunds,
           s.net_sales - COALESCE(r.refunds, 0)                    AS net_revenue,
           s.cogs,
           s.net_sales - COALESCE(r.refunds, 0) - s.cogs           AS gross_profit,
           sh.shipping,
           m.marketing
    FROM sales AS s
    LEFT JOIN refunds   AS r  ON r.month  = s.month
    LEFT JOIN shipping  AS sh ON sh.month = s.month
    LEFT JOIN marketing AS m  ON m.month  = s.month
)
SELECT ROUND(SUM(net_revenue), 0)                          AS total_net_revenue,
       ROUND(SUM(gross_profit), 0)                         AS total_gross_profit,
       ROUND(SUM(shipping), 0)                             AS total_shipping,
       ROUND(SUM(marketing), 0)                            AS total_marketing,
       ROUND(SUM(gross_profit - shipping - marketing), 0)  AS total_operating_profit
FROM pnl;


-- Q2a. Which categories really make money once returns and product costs are counted?
WITH item_lines AS (
    SELECT p.category,
           p.product_name,
           i.quantity * i.unit_price * (1 - o.discount_pct) AS net_sales,
           COALESCE(r.refund_amount, 0)                     AS refund,
           i.quantity * p.unit_cost                         AS cogs
    FROM order_items AS i
    JOIN orders   AS o ON o.order_id   = i.order_id
    JOIN products AS p ON p.product_id = i.product_id
    LEFT JOIN returns AS r ON r.order_item_id = i.order_item_id
    WHERE o.status = 'Delivered'
)
SELECT category,
       ROUND(SUM(net_sales - refund), 0)                                 AS net_revenue,
       ROUND(100.0 * SUM(refund) / SUM(net_sales), 1)                    AS refund_rate_pct,
       ROUND(SUM(net_sales - refund - cogs), 0)                          AS gross_profit,
       ROUND(100.0 * SUM(net_sales - refund - cogs) / SUM(net_sales - refund), 1) AS gross_margin_pct
FROM item_lines
GROUP BY category
ORDER BY gross_profit DESC;


-- Q2b. Top 3 products by gross profit inside each category (window function RANK)
WITH item_lines AS (
    SELECT p.category,
           p.product_name,
           i.quantity * i.unit_price * (1 - o.discount_pct) AS net_sales,
           COALESCE(r.refund_amount, 0)                     AS refund,
           i.quantity * p.unit_cost                         AS cogs
    FROM order_items AS i
    JOIN orders   AS o ON o.order_id   = i.order_id
    JOIN products AS p ON p.product_id = i.product_id
    LEFT JOIN returns AS r ON r.order_item_id = i.order_item_id
    WHERE o.status = 'Delivered'
),
product_profit AS (
    SELECT category,
           product_name,
           ROUND(SUM(net_sales - refund), 0)        AS net_revenue,
           ROUND(SUM(net_sales - refund - cogs), 0) AS gross_profit
    FROM item_lines
    GROUP BY category, product_name
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY category ORDER BY gross_profit DESC) AS rank_in_category
    FROM product_profit
)
SELECT category, rank_in_category, product_name, net_revenue, gross_profit
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;


-- Q3. Which marketing channels bring the most valuable customers?
WITH customer_value AS (
    SELECT o.customer_id,
           COUNT(DISTINCT o.order_id)                                              AS delivered_orders,
           SUM(i.quantity * i.unit_price * (1 - o.discount_pct)
               - COALESCE(r.refund_amount, 0) - i.quantity * p.unit_cost)          AS gross_profit
    FROM orders AS o
    JOIN order_items AS i ON i.order_id   = o.order_id
    JOIN products    AS p ON p.product_id = i.product_id
    LEFT JOIN returns AS r ON r.order_item_id = i.order_item_id
    WHERE o.status = 'Delivered'
    GROUP BY o.customer_id
),
channel_customers AS (
    SELECT c.acquisition_channel                                   AS channel,
           COUNT(*)                                                AS customers,
           AVG(CASE WHEN COALESCE(v.delivered_orders, 0) >= 2 THEN 1.0 ELSE 0 END) AS repeat_rate,
           SUM(COALESCE(v.gross_profit, 0))                        AS gross_profit
    FROM customers AS c
    LEFT JOIN customer_value AS v ON v.customer_id = c.customer_id
    GROUP BY c.acquisition_channel
),
channel_spend AS (
    SELECT channel, SUM(spend_usd) AS spend
    FROM marketing_spend
    GROUP BY channel
)
SELECT cc.channel,
       cc.customers,
       ROUND(COALESCE(cs.spend, 0), 0)                          AS spend,
       ROUND(cs.spend / cc.customers, 2)                        AS cac,
       ROUND(100.0 * cc.repeat_rate, 1)                         AS repeat_rate_pct,
       ROUND(cc.gross_profit / cc.customers, 2)                 AS gross_profit_per_customer,
       ROUND((cc.gross_profit - COALESCE(cs.spend, 0)) / cc.customers, 2) AS profit_after_ads_per_customer
FROM channel_customers AS cc
LEFT JOIN channel_spend AS cs ON cs.channel = cc.channel
ORDER BY profit_after_ads_per_customer DESC;


-- Q4a. Cohort retention (long format): % of each cohort that ordered again N months later
--      Cohort = month of the customer's first delivered order.
--      Copy the result to Excel/Python to draw the heatmap.
WITH delivered AS (
    SELECT o.customer_id, o.order_date, SUBSTR(o.order_date, 1, 7) AS order_month
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id   -- drops unknown customer C9999
    WHERE o.status = 'Delivered'
),
first_order AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM delivered
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT
           f.cohort_month,
           d.customer_id,
           (CAST(SUBSTR(d.order_month, 1, 4) AS INTEGER) - CAST(SUBSTR(f.cohort_month, 1, 4) AS INTEGER)) * 12
         + (CAST(SUBSTR(d.order_month, 6, 2) AS INTEGER) - CAST(SUBSTR(f.cohort_month, 6, 2) AS INTEGER)) AS month_number
    FROM delivered AS d
    JOIN first_order AS f ON f.customer_id = d.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS customers
    FROM first_order
    GROUP BY cohort_month
)
SELECT a.cohort_month,
       s.customers                                       AS cohort_size,
       a.month_number,
       COUNT(*)                                          AS active_customers,
       ROUND(100.0 * COUNT(*) / s.customers, 1)          AS retention_pct
FROM activity AS a
JOIN cohort_size AS s ON s.cohort_month = a.cohort_month
GROUP BY a.cohort_month, a.month_number
ORDER BY a.cohort_month, a.month_number;


-- Q4b. Fair comparison: % of each cohort that placed a 2nd order within 90 days
--      Only cohorts with at least 90 days of history (first order before 2026-04-01).
WITH delivered AS (
    SELECT o.customer_id, o.order_date
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
    WHERE o.status = 'Delivered'
),
numbered AS (
    SELECT customer_id,
           order_date,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS order_number
    FROM delivered
),
first_two AS (
    SELECT customer_id,
           MAX(CASE WHEN order_number = 1 THEN order_date END) AS first_date,
           MAX(CASE WHEN order_number = 2 THEN order_date END) AS second_date
    FROM numbered
    GROUP BY customer_id
)
SELECT SUBSTR(first_date, 1, 7)                                                   AS cohort_month,
       COUNT(*)                                                                   AS customers,
       ROUND(100.0 * AVG(CASE WHEN JULIANDAY(second_date) - JULIANDAY(first_date) <= 90
                              THEN 1.0 ELSE 0 END), 1)                            AS repeat_within_90d_pct
FROM first_two
WHERE first_date < '2026-04-01'
GROUP BY cohort_month
ORDER BY cohort_month;


-- Q5. Was Black Friday 2025 (20-30 Nov) worth it?
--     Compares the campaign days with every other day, per day, on sales and on the customers it brought in.
WITH lines AS (
    SELECT o.order_id,
           o.order_date,
           o.discount_pct,
           CASE WHEN o.order_date BETWEEN '2025-11-20' AND '2025-11-30'
                THEN 'Black Friday' ELSE 'Other days' END                       AS period,
           i.quantity * i.unit_price * (1 - o.discount_pct)
             - COALESCE(r.refund_amount, 0)                                     AS net_revenue,
           i.quantity * i.unit_price * (1 - o.discount_pct)
             - COALESCE(r.refund_amount, 0) - i.quantity * p.unit_cost          AS gross_profit
    FROM orders AS o
    JOIN order_items AS i ON i.order_id   = o.order_id
    JOIN products    AS p ON p.product_id = i.product_id
    LEFT JOIN returns AS r ON r.order_item_id = i.order_item_id
    WHERE o.status = 'Delivered'
)
SELECT period,
       COUNT(DISTINCT order_date)                                        AS days,
       COUNT(DISTINCT order_id)                                          AS orders,
       ROUND(1.0 * COUNT(DISTINCT order_id) / COUNT(DISTINCT order_date), 1) AS orders_per_day,
       ROUND(SUM(net_revenue) / COUNT(DISTINCT order_date), 0)           AS revenue_per_day,
       ROUND(SUM(gross_profit) / COUNT(DISTINCT order_date), 0)          AS gross_profit_per_day,
       ROUND(100.0 * SUM(gross_profit) / SUM(net_revenue), 1)            AS gross_margin_pct
FROM lines
GROUP BY period;


-- Q5b. The customers Black Friday brought in: how valuable were they afterwards?
WITH value AS (
    SELECT o.customer_id,
           COUNT(DISTINCT o.order_id) AS delivered_orders,
           SUM(i.quantity * i.unit_price * (1 - o.discount_pct)
               - COALESCE(r.refund_amount, 0) - i.quantity * p.unit_cost) AS gross_profit
    FROM orders AS o
    JOIN order_items AS i ON i.order_id   = o.order_id
    JOIN products    AS p ON p.product_id = i.product_id
    LEFT JOIN returns AS r ON r.order_item_id = i.order_item_id
    WHERE o.status = 'Delivered'
    GROUP BY o.customer_id
)
SELECT CASE WHEN c.signup_date BETWEEN '2025-11-20' AND '2025-11-30'
            THEN 'Signed up on Black Friday'
            ELSE 'Signed up Sep 2025 - Jan 2026, other days' END            AS customer_group,
       COUNT(*)                                                             AS customers,
       ROUND(100.0 * AVG(CASE WHEN c.acquisition_channel = 'Facebook Ads' THEN 1.0 ELSE 0 END), 1) AS facebook_share_pct,
       ROUND(100.0 * AVG(CASE WHEN COALESCE(v.delivered_orders, 0) >= 2 THEN 1.0 ELSE 0 END), 1) AS repeat_rate_pct,
       ROUND(AVG(COALESCE(v.gross_profit, 0)), 2)                            AS gross_profit_per_customer
FROM customers AS c
LEFT JOIN value AS v ON v.customer_id = c.customer_id
WHERE c.signup_date BETWEEN '2025-09-01' AND '2026-01-31'
GROUP BY customer_group;
