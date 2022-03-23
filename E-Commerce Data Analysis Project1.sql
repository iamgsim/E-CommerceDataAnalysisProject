/* E-Commerce Data and Customer Retention Analysis with SQL */

SELECT NAME
  FROM sys.columns
  WHERE [object_id] = OBJECT_ID('combined_table')
 
SELECT CONVERT(datetime2,(SUBSTRING(Order_Date,7,4) + SUBSTRING(Order_Date,4,2) + SUBSTRING(Order_Date,1,2)) ,101)
FROM orders_dimen

/* Analyze the data by finding the answers to the questions below: */

-- 1. Using the columns of “market_fact”, “cust_dimen”, “orders_dimen”, “prod_dimen”, “shipping_dimen”, Create a new table, named as “combined_table”.

Create view combined_view as
SELECT a.Ord_id, a.prod_id, a.Ship_id, a.Cust_id, a.Sales, a.Discount, a.Order_Quantity, a.Product_Base_Margin,
	   b.Customer_Name, b.Province, b.Region, b.Customer_Segment,
	   c.Order_Date, c.Order_Priority,
	   d.Product_Category, d.Product_Sub_Category,
	   e.Order_ID, e.Ship_Date, e.Ship_Mode
FROM market_fact a 
LEFT JOIN cust_dimen b
ON a.cust_id = b.cust_id
LEFT JOIN orders_dimen c
ON a.ord_id = c.ord_id
LEFT JOIN prod_dimen d
ON a.prod_id = d.prod_id
LEFT JOIN shipping_dimen e
ON a.ship_id = e.ship_id


select * from combined_view

select * into combined_table from combined_view

-- 2. Find the top 3 customers who have the maximum count of orders. 

SELECT TOP 3 COUNT(A.Cust_id), A.Cust_id, a.Customer_Name 
FROM combined_table A 
GROUP BY A.Cust_id, a.Customer_Name
ORDER BY COUNT(A.Cust_id) DESC

-- 3. Create a new column at combined_table as DaysTakenForDelivery that contains the date difference of Order_Date and Ship_Date. 

ALTER TABLE combined_table
ADD DaysTakenForDelivery int;

UPDATE combined_table SET DaysTakenForDelivery = DATEDiFF(day,Order_Date,Ship_Date)

SELECT Cust_id,DaysTakenForDelivery FROM combined_table

-- 4. Find the customer whose order took the maximum time to get delivered.

SELECT Customer_Name,Max(DaysTakenForDelivery) 
FROM combined_table
GROUP BY Customer_Name
ORDER BY Max(DaysTakenForDelivery) DESC

-- 5. Count the total number of unique customers in January and how many of them came back every month over the entire year in 2011

SELECT MONTH(order_date) Aylar,datename(MONTH,Order_Date),Count(DISTINCT Cust_id) Geri_Gelenler
FROM combined_table A
WHERE
		EXISTS(
		SELECT DISTINCT cust_id 
		FROM combined_table B
		WHERE datepart(month,order_date) = 1 
		AND datepart(year,order_date) =2011
		AND a.Cust_id = b.Cust_id
		)
AND datepart(year,order_date) =2011
GROUP BY month(order_date),datename(MONTH,Order_Date)
ORDER BY 1

-- 6. Write a query to return for each user the time elapsed between the first purchasing and the third purchasing, in ascending order by Customer ID.

SELECT DISTINCT cust_id, 
                FIRST_ORDER_DATE [1.order],  
                order_date [3.order], 
                DENSE_NUM,
                DATEDIFF(day,FIRST_ORDER_DATE, order_date) date_diff
 FROM (
      SELECT cust_id, order_date,
      MIN (Order_Date) OVER (PARTITION BY Cust_id) FIRST_ORDER_DATE,
      DENSE_RANK () OVER (PARTITION BY Cust_id ORDER BY Order_date) DENSE_NUM
      FROM combined_table
 ) t1
 WHERE DENSE_NUM =3

-- 7. Write a query that returns customers who purchased both product 11 and product 14, as well as the ratio of these products to the total number of products purchased by the customer.

WITH t1 AS
(
SELECT Cust_id ,
		SUM(CASE WHEN prod_id ='Prod_11' THEN Order_Quantity ELSE 0 END) count_prod11,
		SUM(CASE WHEN prod_id ='Prod_14' THEN Order_Quantity ELSE 0 END) count_prod14,
		SUM(Order_Quantity) Order_Quantity
FROM combined_table
GROUP BY Cust_id
HAVING SUM(CASE WHEN prod_id ='Prod_11' THEN Order_Quantity ELSE 0 END) >0
	AND SUM(CASE WHEN prod_id ='Prod_14' THEN Order_Quantity ELSE 0 END) >0
)
SELECT *,CAST(1.0*count_prod11/Order_Quantity AS DECIMAL (2,2)) prod11_ratio ,
		 CAST(1.0*count_prod14/Order_Quantity AS DECIMAL (2,2)) prod14_ratio
FROM t1


/* Customer Segmentation */

/* Categorize customers based on their frequency of visits. The following steps will guide you. If you want, you can track your own way. */

-- 1. Create a “view” that keeps visit logs of customers on a monthly basis. (For each log, three field is kept: Cust_id, Year, Month)

CREATE VIEW customer_log AS
(
SELECT Cust_id, year(Order_Date) years_, month(Order_Date) month_	
FROM combined_table
GROUP BY Cust_id, year(Order_Date) , month(Order_Date)
)

SELECT * 
FROM [dbo].[customer_log]

-- 2. Create a “view” that keeps the number of monthly visits by users. (Show separately all months from the beginning business)

CREATE view monthly_log AS
(
SELECT
	Cust_id,
	Customer_Name, 
	Order_Date orderdate,
	datepart(YEAR,Order_Date)  years_,
	datename(month,Order_Date) month_,
	count(Order_ID) monthly_visit
FROM combined_table
GROUP BY Cust_id,Customer_Name, datepart(YEAR,Order_Date) , datename(month,Order_Date),Order_Date
)

SELECT *
FROM monthly_log

-- 3. For each visit of customers, create the next month of the visit as a separate column.

CREATE view next_month AS
(
    SELECT *,
		LEAD(Dense_Month, 1) OVER (PARTITION BY Cust_id ORDER BY Dense_Month) next_month
FROM (
    SELECT *,
		dense_rank() OVER(ORDER BY years_,month_) Dense_Month
FROM monthly_log
)a

-- 4. Calculate the monthly time gap between two consecutive visits by each customer.

CREATE view time_gap AS
SELECT Cust_id, order_date, second_order, DATEDIFF(MONTH, order_date, second_order) Month_Gap
FROM (
	SELECT DISTINCT Cust_id, Order_Date,	
	 min(Order_date) OVER(Partition BY Cust_id) first_order_date,	 
	 lead(Order_Date,1) OVER(PARTITION BY cust_id ORDER BY order_date) second_order
	 FROM combined_table
	 ) T

-- 5. Categorise customers using average time gaps. Choose the most fitted labeling model for you.

SELECT cust_id, AVG(Month_Gap) AS AvgTimeGap,
       CASE WHEN AVG(Month_Gap) IS NULL THEN 'Churn'
	     WHEN AVG(Month_Gap) <=1 THEN 'Regular'
	     ELSE 'Irregular'	
       END CustLabels 
FROM time_gap
GROUP BY Cust_id

/* Month-Wise Retention Rate */

/* Find month-by-month customer retention ratei since the start of the business. */

-- 1. Find the number of customers retained month-wise. (You can use time gaps) 

SELECT DISTINCT YEAR(order_date) [year], 
                MONTH(order_date) [month],
                DATENAME(month,order_date) [month_name],
                COUNT(cust_id) OVER (PARTITION BY year(order_date), month(order_date) order by year(order_date), month(order_date)  ) num_cust
FROM combined_table

-- 2. Calculate the month-wise retention rate.

CREATE view month_wise AS
(
SELECT DISTINCT YEAR(order_date) [year], 
                MONTH(order_date) [month],
                DATENAME(month,order_date) [month_name],
                COUNT(cust_id) OVER (PARTITION BY year(order_date), month(order_date) ORDER BY year(order_date), month(order_date)) num_cust
FROM combined_table
)

SELECT year, month, num_cust, lead(num_cust,1) OVER (ORDER BY year, month) rate_,
	FORMAT(num_cust*1.0*100/(lead(num_cust,1) OVER (ORDER BY year, month, num_cust)),'N2')
FROM month_wise