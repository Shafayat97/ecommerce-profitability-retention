-- row check 

SELECT COUNT(*) FROM raw_products;         -- 41
SELECT COUNT(*) FROM raw_customers;        -- 1730
SELECT COUNT(*) FROM raw_orders;           -- 2481
SELECT COUNT(*) FROM raw_order_items;      -- 4150
SELECT COUNT(*) FROM raw_returns;          -- 359
SELECT COUNT(*) FROM raw_marketing_spend;  -- 73


-- duplicate check 


SELECT product_id, COUNT(*) AS times
FROM raw_products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- category duplicate CHECK

SELECT category, COUNT(*) AS products
FROM raw_products
GROUP BY category
ORDER BY category;


-- price integer or text CHECK

SELECT unit_price, typeof(unit_price), unit_cost, typeof(unit_cost)
FROM raw_products
LIMIT 5;

-- Price vs cost check: no issues

SELECT product_id, product_name, unit_price, unit_cost
FROM raw_products
WHERE CAST(REPLACE(REPLACE(unit_price, '$', ''), ',', '') AS REAL) <= unit_cost;
-- signup column date format

SELECT * FROM raw_customers LIMIT 30;

---  duplicate test

SELECT customer_id, COUNT(*) AS times
FROM raw_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- next after finding duplicate

SELECT COUNT(*) FROM (SELECT DISTINCT * FROM raw_customers);

-- acquisition_channel value

SELECT acquisition_channel, COUNT(*)
FROM raw_customers
GROUP BY acquisition_channel
ORDER BY acquisition_channel;

-- empty city

SELECT COUNT(*) FROM raw_customers
WHERE city IS NULL OR TRIM(city) = '';

-- email domain

SELECT SUBSTR(email, INSTR(email, '@') + 1) AS domain, COUNT(*)
FROM raw_customers
GROUP BY domain;


-- date issue 
SELECT COUNT(*) FROM raw_customers WHERE signup_date LIKE '%/%';

-- date format DD/MM/YYYY orি MM/DD/YYYY
SELECT signup_date FROM raw_customers
WHERE signup_date LIKE '%/%'
  AND CAST(SUBSTR(signup_date, 1, 2) AS INTEGER) > 12
LIMIT 10;

