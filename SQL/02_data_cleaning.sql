-- =============================================================
-- 02_data_cleaning.sql  |  NovaCart
-- Builds 6 clean tables from the raw_* tables.
-- Every step follows an Action in data_quality_log_novacart.xlsx.
-- Raw tables are never changed. Run the whole file with F5.
-- =============================================================


-- -------------------------------------------------------------
-- 1. PRODUCTS  (expected: 40 rows)
--    - remove duplicate PR013
--    - standardize category to 5 names
--    - unit_price: remove $ and convert text to number
-- -------------------------------------------------------------
DROP TABLE IF EXISTS products;
CREATE TABLE products AS
SELECT DISTINCT
    product_id,
    TRIM(product_name) AS product_name,
    CASE LOWER(REPLACE(TRIM(category), ' and ', ' & '))
        WHEN 'electronics'    THEN 'Electronics'
        WHEN 'home & kitchen' THEN 'Home & Kitchen'
        WHEN 'fashion'        THEN 'Fashion'
        WHEN 'beauty'         THEN 'Beauty'
        WHEN 'sports'         THEN 'Sports'
    END AS category,
    CAST(REPLACE(REPLACE(unit_price, '$', ''), ',', '') AS REAL) AS unit_price,
    CAST(unit_cost AS REAL) AS unit_cost
FROM raw_products;


-- -------------------------------------------------------------
-- 2. CUSTOMERS  (expected: 1718 rows)
--    - remove 8 duplicate rows
--    - remove 4 test accounts (@novacart.com)
--    - signup_date: DD/MM/YYYY -> YYYY-MM-DD
--    - blank city -> 'Unknown'
--    - standardize acquisition_channel to 5 names
-- -------------------------------------------------------------
DROP TABLE IF EXISTS customers;
CREATE TABLE customers AS
SELECT DISTINCT
    customer_id,
    CASE
        WHEN signup_date LIKE '%/%'
            THEN SUBSTR(signup_date, 7, 4) || '-' || SUBSTR(signup_date, 4, 2) || '-' || SUBSTR(signup_date, 1, 2)
        ELSE TRIM(signup_date)
    END AS signup_date,
    COALESCE(NULLIF(TRIM(city), ''), 'Unknown') AS city,
    CASE LOWER(TRIM(acquisition_channel))
        WHEN 'facebook ads' THEN 'Facebook Ads'
        WHEN 'fb ads'       THEN 'Facebook Ads'
        WHEN 'facebook'     THEN 'Facebook Ads'
        WHEN 'google ads'   THEN 'Google Ads'
        WHEN 'organic'      THEN 'Organic'
        WHEN 'referral'     THEN 'Referral'
        WHEN 'email'        THEN 'Email'
    END AS acquisition_channel,
    LOWER(TRIM(email)) AS email
FROM raw_customers
WHERE email NOT LIKE '%@novacart.com';


-- -------------------------------------------------------------
-- 3. ORDERS  (expected: 2460 rows)
--    - remove 15 duplicate rows
--    - remove 4 test orders and 2 orders with impossible dates
--    - discount_pct: '10%' -> 0.10
--    - keep C9999 orders (real money) and Cancelled orders
--      (filtered out later with status = 'Delivered')
-- -------------------------------------------------------------
DROP TABLE IF EXISTS orders;
CREATE TABLE orders AS
SELECT DISTINCT
    order_id,
    order_date,
    customer_id,
    TRIM(status) AS status,
    CASE
        WHEN INSTR(discount_pct, '%') > 0
            THEN CAST(REPLACE(discount_pct, '%', '') AS REAL) / 100
        ELSE CAST(discount_pct AS REAL)
    END AS discount_pct,
    CAST(shipping_cost AS REAL) AS shipping_cost,
    TRIM(payment_method) AS payment_method
FROM raw_orders
WHERE order_date BETWEEN '2025-01-01' AND '2026-06-30'
  AND customer_id NOT IN (SELECT customer_id FROM raw_customers
                          WHERE email LIKE '%@novacart.com');


-- -------------------------------------------------------------
-- 4. ORDER ITEMS  (expected: 4134 rows)
--    - JOIN products: drops unknown product PR999
--    - JOIN orders:   drops items of test / removed orders
--    - drop quantity <= 0
--    - price 10x the list price -> replace with list price
-- -------------------------------------------------------------
DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items AS
SELECT
    i.order_item_id,
    i.order_id,
    i.product_id,
    CAST(i.quantity AS INTEGER) AS quantity,
    CASE
        WHEN CAST(i.unit_price AS REAL) > p.unit_price * 5 THEN p.unit_price
        ELSE CAST(i.unit_price AS REAL)
    END AS unit_price
FROM raw_order_items AS i
JOIN products AS p ON p.product_id = i.product_id
JOIN orders   AS o ON o.order_id   = i.order_id
WHERE CAST(i.quantity AS INTEGER) > 0;


-- -------------------------------------------------------------
-- 5. RETURNS  (expected: 354 rows)
--    - remove 3 duplicate rows
--    - JOIN order_items: drops 2 returns for items that don't exist
--    - refund larger than the item's value -> cap at item value
-- -------------------------------------------------------------
DROP TABLE IF EXISTS returns;
CREATE TABLE returns AS
SELECT DISTINCT
    r.return_id,
    r.order_item_id,
    r.return_date,
    TRIM(r.reason) AS reason,
    MIN(CAST(r.refund_amount AS REAL),
        ROUND(i.quantity * i.unit_price * (1 - o.discount_pct), 2)) AS refund_amount
FROM raw_returns AS r
JOIN order_items AS i ON i.order_item_id = r.order_item_id
JOIN orders      AS o ON o.order_id      = i.order_id;


-- -------------------------------------------------------------
-- 6. MARKETING SPEND  (expected: 72 rows)
--    - month: 'Jan-2025' -> '2025-01'
--    - standardize channel names
--    - remove 1 duplicate row
-- -------------------------------------------------------------
DROP TABLE IF EXISTS marketing_spend;
CREATE TABLE marketing_spend AS
SELECT DISTINCT
    CASE
        WHEN month LIKE '___-____' THEN
            SUBSTR(month, 5, 4) || '-' ||
            CASE SUBSTR(month, 1, 3)
                WHEN 'Jan' THEN '01' WHEN 'Feb' THEN '02' WHEN 'Mar' THEN '03'
                WHEN 'Apr' THEN '04' WHEN 'May' THEN '05' WHEN 'Jun' THEN '06'
                WHEN 'Jul' THEN '07' WHEN 'Aug' THEN '08' WHEN 'Sep' THEN '09'
                WHEN 'Oct' THEN '10' WHEN 'Nov' THEN '11' WHEN 'Dec' THEN '12'
            END
        ELSE TRIM(month)
    END AS month,
    CASE LOWER(TRIM(channel))
        WHEN 'facebook ads' THEN 'Facebook Ads'
        WHEN 'fb ads'       THEN 'Facebook Ads'
        WHEN 'facebook'     THEN 'Facebook Ads'
        WHEN 'google ads'   THEN 'Google Ads'
        WHEN 'referral'     THEN 'Referral'
        WHEN 'email'        THEN 'Email'
    END AS channel,
    CAST(spend_usd AS REAL) AS spend_usd
FROM raw_marketing_spend;


-- -------------------------------------------------------------
-- 7. CHECK: row counts (compare with 'Row Counts' sheet in the log)
-- -------------------------------------------------------------
SELECT 'products' AS table_name, COUNT(*) AS clean_rows, 40 AS expected FROM products
UNION ALL SELECT 'customers',       COUNT(*), 1718 FROM customers
UNION ALL SELECT 'orders',          COUNT(*), 2460 FROM orders
UNION ALL SELECT 'order_items',     COUNT(*), 4134 FROM order_items
UNION ALL SELECT 'returns',         COUNT(*), 354  FROM returns
UNION ALL SELECT 'marketing_spend', COUNT(*), 72   FROM marketing_spend;
