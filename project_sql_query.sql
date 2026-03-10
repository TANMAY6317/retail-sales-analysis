--CREATE DATABASE
CREATE DATABASE Retail_Analytics;
GO

USE Retail_Analytics;
GO





-- Data Cleaning Step
IF COL_LENGTH('Cleaned Salesdata','order_date_fixed') IS NULL
    ALTER TABLE [Cleaned Salesdata] ADD order_date_fixed DATE;

UPDATE [Cleaned Salesdata]
SET order_date_fixed =
    COALESCE(
        TRY_CONVERT(date, order_date, 23),   
        TRY_CONVERT(date, order_date, 105),  
        TRY_CONVERT(date, order_date)       
    );

SELECT COUNT(*) 
FROM [Cleaned Salesdata]
WHERE order_date_fixed IS NULL;

DELETE FROM [Cleaned Salesdata]
WHERE order_date_fixed IS NULL;

WITH cte AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY signup_date DESC
           ) AS rn
    FROM [Cleaned Customers]
)
DELETE FROM cte
WHERE rn > 1;

WITH cte AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY product_id
               ORDER BY product_name
           ) AS rn
    FROM [Cleaned Products]
)
DELETE FROM cte
WHERE rn > 1;

WITH cte AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY store_id
               ORDER BY store_name
           ) AS rn
    FROM [Cleaned Stores]
)
DELETE FROM cte
WHERE rn > 1;

WITH cte AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY return_id
               ORDER BY return_date DESC
           ) AS rn
    FROM [Cleaned Returns]
)
DELETE FROM cte
WHERE rn > 1;

-- Create Orders table (distinct order_id list)
SELECT DISTINCT
    order_id,
    MIN(order_date_fixed) AS order_date_fixed,   -- safe aggregation
    MIN(customer_id) AS customer_id,
    MIN(store_id) AS store_id,
    MIN(sales_channel) AS sales_channel
INTO Orders
FROM [Cleaned Salesdata]
GROUP BY order_id;

ALTER TABLE Orders
ADD CONSTRAINT PK_Orders PRIMARY KEY (order_id);




-- PRIMARY KEYS

ALTER TABLE [Cleaned Customers]
ADD CONSTRAINT PK_Customers PRIMARY KEY (customer_id);

ALTER TABLE [Cleaned Salesdata]
ADD sales_line_id INT IDENTITY(1,1);

ALTER TABLE [Cleaned Salesdata]
ADD CONSTRAINT PK_Sales PRIMARY KEY (sales_line_id);

ALTER TABLE [Cleaned Products]
ADD CONSTRAINT PK_Products PRIMARY KEY (product_id);

ALTER TABLE [Cleaned Stores]
ADD CONSTRAINT PK_Stores PRIMARY KEY (store_id);

ALTER TABLE [Cleaned Returns]
ADD CONSTRAINT PK_Returns PRIMARY KEY (return_id);

-- FOREIGN KEYS

ALTER TABLE [Cleaned Salesdata]
ADD CONSTRAINT FK_Sales_Orders
FOREIGN KEY (order_id)
REFERENCES Orders(order_id);

ALTER TABLE [Cleaned Salesdata]
ADD CONSTRAINT FK_Sales_Customers
FOREIGN KEY (customer_id)
REFERENCES [Cleaned Customers](customer_id);

ALTER TABLE [Cleaned Salesdata]
ADD CONSTRAINT FK_Sales_Products
FOREIGN KEY (product_id)
REFERENCES [Cleaned Products](product_id);

ALTER TABLE [Cleaned Salesdata]
ADD CONSTRAINT FK_Sales_Stores
FOREIGN KEY (store_id)
REFERENCES [Cleaned Stores](store_id);

ALTER TABLE [Cleaned Returns]
ADD CONSTRAINT FK_Returns_Orders
FOREIGN KEY (order_id)
REFERENCES Orders(order_id);




--BUSINESS QUESTIONS



--1. What is the total revenue generated in the last 12 months? 
SELECT SUM(total_amount) AS total_revenue_last_12_months
FROM [Cleaned Salesdata]
WHERE order_date_fixed >= DATEADD(
    MONTH, -12,
    (SELECT MAX(order_date_fixed) FROM [Cleaned Salesdata])
);

--2. Which are the top 5 best-selling products by quantity? 
SELECT TOP 5
       s.product_id,
       p.product_name,
       SUM(s.quantity) AS total_quantity
FROM [Cleaned Salesdata] s
JOIN [Cleaned Products] p
     ON s.product_id = p.product_id
GROUP BY s.product_id, p.product_name
ORDER BY total_quantity DESC;

--3. How many customers are from each region? 
SELECT region,
       COUNT(*) AS total_customers
FROM [Cleaned Customers]
GROUP BY region
ORDER BY total_customers DESC;

--4. Which store has the highest profit in the past year? 
--Profit = total_amount - (cost_price × quantity)
SELECT TOP 1
       st.store_name,
       SUM(s.total_amount - (p.cost_price * s.quantity)) AS total_profit
FROM [Cleaned Salesdata] s
JOIN [Cleaned Products] p
     ON s.product_id = p.product_id
JOIN [Cleaned Stores] st
     ON s.store_id = st.store_id
WHERE s.order_date_fixed >= DATEADD(
      MONTH, -12,
      (SELECT MAX(order_date_fixed) FROM [Cleaned Salesdata])
)
GROUP BY st.store_name
ORDER BY total_profit DESC;

--5. What is the return rate by product category? 
SELECT p.category,
       CAST(COUNT(r.order_id) AS FLOAT) 
       / NULLIF(COUNT(s.order_id), 0) AS return_rate
FROM [Cleaned Salesdata] s
LEFT JOIN [Cleaned Returns] r
     ON s.order_id = r.order_id
JOIN [Cleaned Products] p
     ON s.product_id = p.product_id
GROUP BY p.category
ORDER BY return_rate DESC;

--6. What is the average revenue per customer by age group? 
WITH customer_age_group AS (
    SELECT 
        customer_id,
        CASE 
            WHEN age < 25 THEN 'Under 25'
            WHEN age BETWEEN 25 AND 40 THEN '25-40'
            WHEN age BETWEEN 41 AND 60 THEN '41-60'
            ELSE '60+'
        END AS age_group
    FROM [Cleaned Customers]
)
SELECT 
    cag.age_group,
    AVG(s.total_amount) AS avg_revenue
FROM [Cleaned Salesdata] s
JOIN customer_age_group cag
    ON s.customer_id = cag.customer_id
GROUP BY cag.age_group
ORDER BY avg_revenue DESC;

--7. Which sales channel (Online vs In-Store) is more profitable on average? 
SELECT s.sales_channel,
       AVG(s.total_amount - (p.cost_price * s.quantity)) AS avg_profit
FROM [Cleaned Salesdata] s
JOIN [Cleaned Products] p
     ON s.product_id = p.product_id
GROUP BY s.sales_channel
ORDER BY avg_profit DESC;

--8. How has monthly profit changed over the last 2 years by region? 
SELECT FORMAT(s.order_date_fixed, 'yyyy-MM') AS year_month,
       st.region,
       SUM(s.total_amount - (p.cost_price * s.quantity)) AS monthly_profit
FROM [Cleaned Salesdata] s
JOIN [Cleaned Products] p
     ON s.product_id = p.product_id
JOIN [Cleaned Stores] st
     ON s.store_id = st.store_id
WHERE s.order_date_fixed >= DATEADD(
        YEAR, -2,
        (SELECT MAX(order_date_fixed)
         FROM [Cleaned Salesdata])
)
GROUP BY FORMAT(s.order_date_fixed, 'yyyy-MM'), st.region
ORDER BY year_month;

--9. Identify the top 3 products with the highest return rate in each category. 
WITH ranked_products AS (
    SELECT p.category,
           p.product_name,
           CAST(COUNT(r.order_id) AS FLOAT) / COUNT(s.order_id) AS return_rate,
           ROW_NUMBER() OVER (
               PARTITION BY p.category
               ORDER BY CAST(COUNT(r.order_id) AS FLOAT) / COUNT(s.order_id) DESC
           ) AS rank_num
    FROM [Cleaned Salesdata] s
    LEFT JOIN [Cleaned Returns] r
         ON s.order_id = r.order_id
    JOIN [Cleaned Products] p
         ON s.product_id = p.product_id
    GROUP BY p.category, p.product_name
)
SELECT *
FROM ranked_products
WHERE rank_num <= 3;

--10. Which 5 customers have contributed the most to total profit, and what is their tenure with the company?
SELECT TOP 5
       c.customer_id,
       c.first_name,
       c.last_name,
       SUM(s.total_amount - (p.cost_price * s.quantity)) AS total_profit,
       DATEDIFF(DAY, c.signup_date,
                (SELECT MAX(order_date_fixed)
                 FROM [Cleaned Salesdata])) / 365.0 AS tenure_years
FROM [Cleaned Salesdata] s
JOIN [Cleaned Customers] c
     ON s.customer_id = c.customer_id
JOIN [Cleaned Products] p
     ON s.product_id = p.product_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.signup_date
ORDER BY total_profit DESC;