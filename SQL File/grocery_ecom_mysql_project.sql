/*=================================================================*
	ZEPTO ONLINE PLATFORM PERFORMANCE
 *=================================================================*/

-- *********************************************************************
-- 0. PROJECT SETUP
-- *********************************************************************

CREATE DATABASE grocery_ecom;
USE grocery_ecom;

SET SQL_SAFE_UPDATES = 0;
SET SQL_SAFE_UPDATES = 1;
-- *********************************************************************
-- 1. DATA PREPARATION (tables, constraints, validation checks, cleaning)
-- *********************************************************************
-- =========================
-- 1.1 DATA QUALITY / VALIDATION CHECKS
-- =========================

-- 1.1 Record counts per table
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'payments', COUNT(*) FROM payments;

-- 1.2 Duplicate checks

-- Duplicate emails
SELECT email, COUNT(*) AS cnt
FROM customers
WHERE email IS NOT NULL
GROUP BY email
HAVING cnt > 1;

-- Duplicate phone numbers
SELECT phone_number, COUNT(*) AS cnt
FROM customers
WHERE phone_number IS NOT NULL
GROUP BY phone_number
HAVING cnt > 1;

-- Order items with same order + product multiple times
SELECT order_id, product_id, COUNT(*) AS item_count
FROM order_items
GROUP BY order_id, product_id
HAVING item_count > 1;

-- 1.3 NULL / Missing critical data

-- Customers missing contact info
SELECT *
FROM customers
WHERE (email IS NULL OR email = '')
   OR (phone_number IS NULL OR phone_number = '');

-- Orders missing payment_method or total_amount
SELECT *
FROM orders
WHERE payment_method IS NULL
   OR total_amount IS NULL;

-- Payments with missing payment_time or payment_status
SELECT *
FROM payments
WHERE payment_time IS NULL
   OR payment_status IS NULL;

-- 1.4 Logical checks

-- Orders with total_amount not matching sum of order_items (rough check)
SELECT
    o.order_id,
    o.total_amount,
    SUM(oi.line_total) AS sum_line_total
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
HAVING ABS(o.total_amount - SUM(oi.line_total)) > 0.01;

-- Payments referencing unknown orders
SELECT p.*
FROM payments p
LEFT JOIN orders o ON o.order_id = p.order_id
WHERE o.order_id IS NULL;

-- Orders referencing unknown customers
SELECT o.*
FROM orders o
LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

-- 1.5 Date checks

-- Payment time before order time
SELECT p.*
FROM payments p
JOIN orders o ON o.order_id = p.order_id
WHERE p.payment_time < o.order_date;

-- =========================
-- 1.2 SAMPLE DATA CLEANING ACTIONS
-- =========================

-- 1.2.1 Trim whitespace
UPDATE customers
SET full_name = TRIM(full_name),
    email      = TRIM(email),
    city       = TRIM(city);

UPDATE products
SET product_name = TRIM(product_name),
    category     = TRIM(category),
    brand        = TRIM(brand),
    unit         = TRIM(unit);

UPDATE orders
SET delivery_partner = TRIM(delivery_partner);

UPDATE payments
SET transaction_id = TRIM(transaction_id);

-- 1.2.2 Standardize gender case
UPDATE customers
SET gender = 'Male'
WHERE gender IS NOT NULL AND LOWER(gender) = 'male';

UPDATE customers
SET gender = 'Female'
WHERE gender IS NOT NULL AND LOWER(gender) = 'female';

UPDATE customers
SET gender = 'Other'
WHERE gender IS NOT NULL AND LOWER(gender) NOT IN ('male','female','other');

-- 1.2.3 Fix negative amounts or stock
UPDATE products
SET price = ABS(price),
    stock_quantity = ABS(stock_quantity)
WHERE price < 0 OR stock_quantity < 0;

UPDATE order_items
SET unit_price = ABS(unit_price),
    line_total = ABS(line_total)
WHERE unit_price < 0 OR line_total < 0;

UPDATE orders
SET total_amount = ABS(total_amount)
WHERE total_amount < 0;

-- *********************************************************************
-- 2. DATA MODELLING (FK relationships, analytic views)
-- *********************************************************************

-- =========================
-- 2.1 ANALYTIC VIEWS
-- =========================

-- 2.1.1 Customer overview
DROP VIEW IF EXISTS vw_customer_overview;
CREATE VIEW vw_customer_overview AS
SELECT
    c.customer_id,
    c.full_name,
    c.email,
    c.city,
    c.gender,
    c.registration_date,
    c.loyalty_points,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(o.total_amount)        AS total_spent,
    MIN(o.order_date)          AS first_order_date,
    MAX(o.order_date)          AS last_order_date
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.full_name,
    c.email,
    c.city,
    c.gender,
    c.registration_date,
    c.loyalty_points;

-- 2.1.2 Product performance
DROP VIEW IF EXISTS vw_product_performance;
CREATE VIEW vw_product_performance AS
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.brand,
    p.price,
    p.stock_quantity,
    SUM(oi.quantity)                  AS total_qty_sold,
    SUM(oi.line_total)                AS total_revenue,
    COUNT(DISTINCT oi.order_id)       AS orders_count
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.product_id
GROUP BY
    p.product_id,
    p.product_name,
    p.category,
    p.brand,
    p.price,
    p.stock_quantity;

-- 2.1.3 Daily sales summary
DROP VIEW IF EXISTS vw_daily_sales;
CREATE VIEW vw_daily_sales AS
SELECT
    DATE(o.order_date) AS order_date,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(o.total_amount)        AS total_revenue,
    AVG(o.total_amount)        AS avg_order_value
FROM orders o
GROUP BY DATE(o.order_date);

-- *********************************************************************
-- 3. DATA ANALYSIS (KPI queries, churn, revenue, segmentation)
-- *********************************************************************

-- =========================
-- 3.1 OVERALL KPIs
-- =========================

-- 3.1.1 Total customers, orders, revenue
SELECT
    (SELECT COUNT(*) FROM customers)   AS total_customers,
    (SELECT COUNT(*) FROM orders)      AS total_orders,
    (SELECT SUM(total_amount) FROM orders) AS total_revenue;

-- 3.1.2 Orders by status
SELECT
    order_status,
    COUNT(*) AS order_count,
    SUM(total_amount) AS revenue
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;

-- 3.1.3 Revenue by payment_method
SELECT
    payment_method,
    COUNT(DISTINCT o.order_id) AS orders_count,
    SUM(o.total_amount)        AS total_revenue
FROM orders o
GROUP BY payment_method
ORDER BY total_revenue DESC;

-- =========================
-- 3.2 CUSTOMER ANALYSIS
-- =========================

-- 3.2.1 Top 10 customers by spend
SELECT *
FROM vw_customer_overview
ORDER BY total_spent DESC
LIMIT 10;

-- 3.2.2 Customers by city
SELECT
    city,
    COUNT(*) AS customer_count,
    SUM(loyalty_points) AS total_loyalty_points
FROM customers
GROUP BY city
ORDER BY customer_count DESC;

-- 3.2.3 Churn-style: customers with no orders in last 90 days
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    coalesce(v.last_order_date, c.registration_date) AS last_order_date
FROM customers c
LEFT JOIN vw_customer_overview v ON v.customer_id = c.customer_id
WHERE v.last_order_date IS NULL
   OR v.last_order_date < DATE_SUB(CURDATE(), INTERVAL 90 DAY)
ORDER BY last_order_date;

-- =========================
-- 3.3 PRODUCT & CATEGORY ANALYSIS
-- =========================

-- 3.3.1 Top 10 products by revenue
SELECT *
FROM vw_product_performance
ORDER BY total_revenue DESC
LIMIT 10;

-- 3.3.2 Sales by category
SELECT
    p.category,
    SUM(oi.line_total) AS category_revenue,
    SUM(oi.quantity)   AS category_qty
FROM products p
JOIN order_items oi ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY category_revenue DESC;

-- 3.3.3 Average basket size (items per order)
SELECT
    AVG(items_per_order) AS avg_items_per_order
FROM (
    SELECT
        order_id,
        SUM(quantity) AS items_per_order
    FROM order_items
    GROUP BY order_id
) t;

-- =========================
-- 3.4 OPERATIONAL METRICS
-- =========================

-- 3.4.1 Average delivery time by partner
SELECT
    delivery_partner,
    COUNT(*) AS orders_count,
    AVG(delivery_time_mins) AS avg_delivery_time_mins
FROM orders
GROUP BY delivery_partner
ORDER BY avg_delivery_time_mins;

-- 3.4.2 Payment success vs failure
SELECT
    payment_status,
    COUNT(*) AS count_status
FROM payments
GROUP BY payment_status;

-- *********************************************************************
-- 4. PRESENTATION 
-- *********************************************************************

-- =========================
-- 4.1 DIMENSION & FACT VIEWS
-- =========================

-- Customer dimension
DROP VIEW IF EXISTS vw_dim_customer;
CREATE VIEW vw_dim_customer AS
SELECT
    customer_id,
    full_name,
    email,
    phone_number,
    gender,
    city,
    registration_date,
    loyalty_points
FROM customers;

-- Product dimension
DROP VIEW IF EXISTS vw_dim_product;
CREATE VIEW vw_dim_product AS
SELECT
    product_id,
    product_name,
    category,
    brand,
    price,
    unit
FROM products;

-- Order fact
DROP VIEW IF EXISTS vw_fact_order;
CREATE VIEW vw_fact_order AS
SELECT
    order_id,
    customer_id,
    order_date,
    order_status,
    payment_method,
    total_amount,
    delivery_time_mins,
    delivery_partner
FROM orders;

-- Order item fact
DROP VIEW IF EXISTS vw_fact_order_item;
CREATE VIEW vw_fact_order_item AS
SELECT
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    line_total
FROM order_items;

-- Payment fact
DROP VIEW IF EXISTS vw_fact_payment;
CREATE VIEW vw_fact_payment AS
SELECT
    payment_id,
    order_id,
    payment_method,
    payment_status,
    transaction_id,
    payment_time
FROM payments;

-- =========================
-- 4.2 MONTHLY SALES SUMMARY TABLE
-- =========================

DROP TABLE IF EXISTS fact_monthly_sales;
CREATE TABLE fact_monthly_sales (
    year_month       CHAR(7) PRIMARY KEY,  -- 'YYYY-MM'
    total_orders     INT,
    total_revenue    DECIMAL(18,2),
    avg_order_value  DECIMAL(18,2)
) ENGINE=InnoDB;

-- Initial load
INSERT INTO fact_monthly_sales (year_month, total_orders, total_revenue, avg_order_value)
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS year_month,
    COUNT(*) AS total_orders,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_order_value
FROM orders
GROUP BY DATE_FORMAT(order_date, '%Y-%m');

-- *********************************************************************
-- 5. IMPROVEMENTS (indexes, stored procedures, events, risk flags)
-- *********************************************************************

-- 5.1 ADDITIONAL INDEXES

-- Fast filter by city & registration_date
CREATE INDEX idx_customers_city_reg
    ON customers (city, registration_date);

-- Fast category + brand combination search
CREATE INDEX idx_products_cat_brand
    ON products (category, brand);

-- Fast order search by date and customer
CREATE INDEX idx_orders_date_customer
    ON orders (order_date, customer_id);

-- 5.2 STORED PROCEDURE TO REFRESH MONTHLY SALES SUMMARY

DROP PROCEDURE IF EXISTS sp_refresh_monthly_sales;
DELIMITER $$
CREATE PROCEDURE sp_refresh_monthly_sales()
BEGIN
    TRUNCATE TABLE fact_monthly_sales;

    INSERT INTO fact_monthly_sales (year_month, total_orders, total_revenue, avg_order_value)
    SELECT
        DATE_FORMAT(order_date, '%Y-%m') AS year_month,
        COUNT(*) AS total_orders,
        SUM(total_amount) AS total_revenue,
        AVG(total_amount) AS avg_order_value
    FROM orders
    GROUP BY DATE_FORMAT(order_date, '%Y-%m');
END$$
DELIMITER ;

-- 5.3 EVENT TO AUTO-REFRESH MONTHLY (if event_scheduler=ON)

DROP EVENT IF EXISTS ev_refresh_monthly_sales;
DELIMITER $$
CREATE EVENT ev_refresh_monthly_sales
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_DATE + INTERVAL 1 MONTH
DO
    CALL sp_refresh_monthly_sales();
$$
DELIMITER ;

-- *********************************************************************
-- END OF SCRIPT
-- *********************************************************************
