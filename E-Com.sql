SELECT
   *
FROM
    xomdata_dataset.e_commerce.customer;

-- Q1: What is our actual P&L; by segment and category — including every loss-making order?
SELECT
    s.segment,
    p.category,
    SUM(s.sales)                                           AS gross_revenue,
    SUM(s.profit)                                          AS gross_profit,
    ROUND(SUM(s.profit) / NULLIF(SUM(s.sales), 0) * 100, 2) AS gross_margin_pct,
    COUNT(*)                                               AS total_order_lines,
    SUM(CASE WHEN s.profit < 0 THEN 1 ELSE 0 END)         AS loss_line_count,
    ROUND(
        SUM(CASE WHEN s.profit < 0 THEN 1.0 ELSE 0 END)
        / NULLIF(COUNT(*), 0) * 100, 2
    )                                                      AS loss_line_rate_pct
FROM       e_commerce.ecom_sales  s
INNER JOIN e_commerce.product     p ON s.product_code = p.product_code
GROUP BY   s.segment, p.category
ORDER BY   s.segment, gross_profit DESC;

--Q2: What fraction of our customers actually come back — and how does repeat behaviour differ by segment?
WITH order_level AS (
    SELECT
        s.order_id,
        s.customer_id,
        p.category,
        ROW_NUMBER() OVER (PARTITION BY s.order_id, p.category ORDER BY (SELECT NULL)) AS rn
    FROM e_commerce.ecom_sales s
    INNER JOIN e_commerce.product p ON s.product_code = p.product_code
),
unique_orders AS (
    SELECT order_id, customer_id, category
    FROM order_level
    WHERE rn = 1
),
customer_order_counts AS (
    SELECT
        customer_id,
        category,
        COUNT(order_id) AS orders_in_category
    FROM unique_orders
    GROUP BY customer_id, category
)
SELECT
    category,
    COUNT(DISTINCT customer_id)                                               AS unique_customers,
    SUM(orders_in_category)                                                   AS total_orders,
    SUM(CASE WHEN orders_in_category = 1 THEN 1 ELSE 0 END)                  AS one_time_count,
    SUM(CASE WHEN orders_in_category = 2 THEN 1 ELSE 0 END)                  AS two_order_count,
    SUM(CASE WHEN orders_in_category >= 3 THEN 1 ELSE 0 END)                 AS repeat_3plus_count,
    ROUND(
        SUM(CASE WHEN orders_in_category >= 2 THEN 1.0 ELSE 0 END)
        / NULLIF(COUNT(DISTINCT customer_id), 0) * 100, 2
    )                                                                         AS repeat_rate_pct,
    ROUND(SUM(orders_in_category) * 1.0
        / NULLIF(COUNT(DISTINCT customer_id), 0), 2)                         AS avg_orders_per_customer
FROM customer_order_counts
GROUP BY category
ORDER BY repeat_rate_pct DESC;

-- Q3: Which subcategories rank highest by revenue — and do they rank the same by profit?
WITH ranked AS (
    SELECT
        p.category,
    	p.subcategory,
        SUM(s.sales)                                      AS total_revenue,
        SUM(s.profit)                                     AS total_profit,
        ROUND(SUM(s.profit) / NULLIF(SUM(s.sales), 0) * 100, 2) AS margin_pct,
        RANK() OVER (ORDER BY SUM(s.sales) DESC)          AS revenue_rank,
        RANK() OVER (ORDER BY SUM(s.profit) DESC)         AS profit_rank
    FROM e_commerce.ecom_sales  s
    INNER JOIN e_commerce.product p ON s.product_code = p.product_code
    GROUP BY p.category , p.subcategory
)
SELECT
    category,
	subcategory,
    total_revenue,
    total_profit,
    margin_pct,
    revenue_rank,
    profit_rank,
    revenue_rank - profit_rank   AS rank_gap
FROM ranked
ORDER BY revenue_rank;

-- Q4: Does discounting actually generate incremental volume, or does it only destroy margin?
WITH order_level AS (
    SELECT
        s.order_id,
        p.category,
        s.discount,
        s.sales,
        s.profit,
        CASE
            WHEN s.discount = 0          THEN 'No Discount'
            WHEN s.discount <= 0.1       THEN 'Low (1-10%)'
            WHEN s.discount <= 0.2       THEN 'Mid (11-20%)'
            ELSE                              'High (>20%)'
        END AS discount_tier,
        ROW_NUMBER() OVER (PARTITION BY s.order_id ORDER BY (SELECT NULL)) AS rn
    FROM e_commerce.ecom_sales  s
    INNER JOIN e_commerce.product p ON s.product_code = p.product_code
),
line_level AS (
    SELECT
        category,
        discount_tier,
        discount,
        sales,
        profit
    FROM order_level
)
SELECT
    category,
    discount_tier,
    COUNT(*)                                                        AS line_count,
    ROUND(AVG(discount) * 100, 2)                                   AS avg_discount_pct,
    ROUND(SUM(sales), 2)                                            AS total_revenue,
    ROUND(SUM(profit), 2)                                           AS total_profit,
    ROUND(SUM(profit) / NULLIF(SUM(sales), 0) * 100, 2)            AS margin_pct,
    ROUND(AVG(sales), 2)                                            AS avg_order_line_value
FROM line_level
GROUP BY category, discount_tier
ORDER BY category, avg_discount_pct;

--Q5: Which segment produces the most profitable customers on a per-head basis — and what is the distribution of customer-level profit?
WITH customer_profit AS (
    SELECT
        customer_id,
        segment,
        SUM(profit) AS profit_in_segment
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, segment
),
distribution AS (
    SELECT
        customer_id,
        segment,
        profit_in_segment,
        NTILE(4) OVER (
            PARTITION BY segment
            ORDER BY profit_in_segment
        ) AS profit_quartile
    FROM customer_profit
)
-- Query 1: customer level
SELECT
    d.segment,
    c.customer_id,
    c.annual_income,
    c.education_level,
    c.occupation,
    c.home_owner,
    d.profit_in_segment,
    d.profit_quartile
FROM distribution d
INNER JOIN e_commerce.customer c ON c.customer_id = d.customer_id
ORDER BY d.profit_in_segment DESC, d.segment DESC;

-- Query 2: segment level
WITH customer_profit AS (
    SELECT
        customer_id,
        segment,
        SUM(profit) AS profit_in_segment
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, segment
),
distribution AS (
    SELECT
        customer_id,
        segment,
        profit_in_segment,
        NTILE(4) OVER (
            PARTITION BY segment
            ORDER BY profit_in_segment
        ) AS profit_quartile
    FROM customer_profit
)
SELECT
    segment,
    COUNT(DISTINCT customer_id)                                             AS unique_customers,
    ROUND(AVG(profit_in_segment), 2)                                        AS avg_profit_per_customer,
    ROUND(SUM(profit_in_segment), 2)                                        AS total_profit,
    ROUND(MIN(profit_in_segment), 2)                                        AS min_profit,
    ROUND(MAX(profit_in_segment), 2)                                        AS max_profit,
    SUM(CASE WHEN profit_in_segment < 0 THEN 1 ELSE 0 END)                 AS negative_profit_customers,
    ROUND(
        SUM(CASE WHEN profit_quartile = 4 THEN profit_in_segment ELSE 0 END)
        / NULLIF(SUM(profit_in_segment), 0) * 100, 2
    )                                                                       AS top25_profit_share_pct
FROM distribution
GROUP BY segment
ORDER BY avg_profit_per_customer DESC;

-- Q6: Which markets are growing and which are saturating — and how does growth rate interact with profitability?
-- YoY by market
WITH sales_by_market AS(
SELECT 
	r.market,
	DATEFROMPARTS(YEAR(es.order_date), MONTH(es.order_date),1) AS month_start,
	ROUND(SUM(es.sales),2) AS monthly_sales
FROM e_commerce.ecom_sales es
INNER JOIN e_commerce.region r 
ON es.region_code = r.region_code
GROUP BY r.market, YEAR(es.order_date), MONTH(es.order_date)
),

yoy_calc AS (
    SELECT
        market,
        month_start,
        monthly_sales,
        LAG(monthly_sales, 12) OVER (
            PARTITION BY market
            ORDER BY month_start
        )                                         AS sales_same_month_last_year
    FROM sales_by_market
   )
   
   SELECT
    market,
    month_start,
    monthly_sales,
    sales_same_month_last_year,
    ROUND(
        (monthly_sales - sales_same_month_last_year)
        / NULLIF(sales_same_month_last_year, 0) * 100, 2
    )                                                            AS yoy_growth_pct
FROM yoy_calc
WHERE sales_same_month_last_year IS NOT NULL
ORDER BY market, month_start;

-- Total YoY within latest 24 months
WITH monthly AS (
    SELECT
        DATEFROMPARTS(YEAR(es.order_date), MONTH(es.order_date), 1) AS month_start,
        SUM(es.sales)  AS monthly_sales,
        SUM(es.profit) AS monthly_profit
    FROM e_commerce.ecom_sales es
    GROUP BY YEAR(es.order_date), MONTH(es.order_date)
),
yoy_calc AS (
    SELECT
        month_start,
        monthly_sales,
        monthly_profit,
        LAG(monthly_sales, 12)  OVER (ORDER BY month_start) AS sales_last_year,
    FROM monthly
),
bounds AS (
    SELECT MAX(month_start) AS last_month FROM monthly
)
SELECT
    FORMAT(y.month_start, 'yyyy-MM')                                    AS year_month,
    ROUND(y.monthly_sales, 2)                                           AS monthly_sales,
    ROUND(y.sales_last_year, 2)                                         AS sales_last_year,
    ROUND(
        (y.monthly_sales - y.sales_last_year)
        / NULLIF(y.sales_last_year, 0) * 100, 2
    )                                                                   AS yoy_sales_growth_pct
FROM yoy_calc y
CROSS JOIN bounds b
WHERE y.month_start >= DATEADD(MONTH, -23, b.last_month)
ORDER BY y.month_start;


-- Q7: In the highest-revenue category — which subcategories destroy the most profit, and what is the structural discount driving it?
WITH sales_category AS(
SELECT 
		p.category,
		ROUND(SUM(es.sales),2) AS total_sales 
FROM e_commerce.product p 
INNER JOIN e_commerce.ecom_sales es
ON p.product_code = es.product_code
GROUP BY p.category 
),

top_sales_category AS(
 SELECT TOP 1 category
    FROM sales_category
 ORDER BY total_sales DESC
),

top_sub_sales AS(
	SELECT 
		p.subcategory,
		ROUND(SUM(es.sales),2) 												AS total_sales,
		ROUND(SUM(es.profit),2) 												AS total_profit,
		ROUND(AVG(es.discount)*100, 2) 								AS avg_discount_rate,
		SUM(CASE WHEN es.profit < 0 THEN 1 ELSE 0 END) 				AS loss_line_count,
		ROUND(SUM(CASE WHEN es.profit < 0 THEN 1.0 ELSE 0 END) / 
			NULLIF(COUNT(*), 0) * 100, 2)   						AS loss_line_rate
	FROM e_commerce.ecom_sales es
	INNER JOIN e_commerce.product p
	ON p.product_code = es.product_code
	WHERE p.category = (SELECT category FROM top_sales_category)
	GROUP BY p.subcategory 
)

SELECT 
	subcategory,
	total_sales,
	total_profit,
	avg_discount_rate,
	loss_line_count,
	loss_line_rate
FROM top_sub_sales
ORDER BY loss_line_rate DESC;

-- Q8: Which customers are at risk of churning in the next 90 days — and how much revenue are they collectively worth?
WITH unique_orders AS (
    SELECT DISTINCT customer_id, segment, order_date
    FROM e_commerce.ecom_sales
),
purchase_gaps AS (
    SELECT
        customer_id,
        segment,
        order_date,
        DATEDIFF(DAY,
            LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date),
            order_date
        ) AS gap_days
    FROM unique_orders
),
bounds AS (
    SELECT MAX(order_date) AS latest_date FROM e_commerce.ecom_sales
),
order_counts AS (
    SELECT customer_id, COUNT(DISTINCT order_date) AS total_orders
    FROM unique_orders
    GROUP BY customer_id
),
segment_avg_interval AS (
    SELECT g.segment,
        AVG(CAST(g.gap_days AS FLOAT)) AS avg_interval
    FROM purchase_gaps g
    INNER JOIN order_counts o ON g.customer_id = o.customer_id
    WHERE o.total_orders >= 3
      AND g.gap_days IS NOT NULL
    GROUP BY g.segment
),
customer_last_order AS (
    SELECT
        customer_id,
        segment,
        MAX(order_date) AS last_order,
        SUM(sales)      AS lifetime_sales
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, segment
),
churn_tier AS (
    SELECT
        c.customer_id,
        c.segment,
        c.last_order,
        ROUND(c.lifetime_sales, 2)                              AS lifetime_sales,
        DATEDIFF(DAY, c.last_order, b.latest_date)             AS days_since,
        ROUND(s.avg_interval, 1)                               AS segment_avg_interval,
        ROUND(DATEDIFF(DAY, c.last_order, b.latest_date)
              / NULLIF(s.avg_interval, 0), 2)                  AS ratio,
        CASE
            WHEN DATEDIFF(DAY, c.last_order, b.latest_date)
                 / NULLIF(s.avg_interval, 0) < 0.75  THEN 'GREEN'
            WHEN DATEDIFF(DAY, c.last_order, b.latest_date)
                 / NULLIF(s.avg_interval, 0) < 1.5   THEN 'AMBER'
            WHEN DATEDIFF(DAY, c.last_order, b.latest_date)
                 / NULLIF(s.avg_interval, 0) < 3.0   THEN 'RED'
            ELSE 'GREY'
        END AS churn_tier
    FROM customer_last_order c
    INNER JOIN segment_avg_interval s ON s.segment = c.segment
    CROSS JOIN bounds b
)
SELECT
    customer_id,
    segment,
    last_order,
    days_since,
    segment_avg_interval,
    ratio,
    churn_tier,
    lifetime_sales
FROM churn_tier
ORDER BY
    CASE churn_tier WHEN 'RED' THEN 1 WHEN 'AMBER' THEN 2 WHEN 'GREY' THEN 3 ELSE 4 END,
    lifetime_sales DESC;

-- Q9: What does the RFM landscape look like — and which RFM segments are generating disproportionate profit vs. disproportionate revenue?
WITH reference_date AS(
SELECT 
	max(order_date) AS ref_date
FROM e_commerce.ecom_sales es 
),

rfm_raw AS(
SELECT 
		es.customer_id,
		DATEDIFF(DAY, MAX(es.order_date),r.ref_date)  AS recency,
		COUNT(DISTINCT order_id) AS frequency,
		SUM(profit) AS monetary,
		SUM(sales) AS total_sales
FROM e_commerce.ecom_sales es
CROSS JOIN reference_date r
GROUP BY es.customer_id, r.ref_date
),

rfm_score AS(
SELECT
		customer_id,
		total_sales, monetary,
		NTILE(4) OVER(ORDER BY recency ASC) as R_score,
		NTILE(4) OVER(ORDER BY frequency DESC) as F_score,
		NTILE(4) OVER(ORDER BY monetary DESC) as M_score
FROM rfm_raw
),

rfm_labeled AS(
SELECT 
		customer_id,
		R_score, F_score, M_score, total_sales, monetary,
		CASE
            WHEN R_score = 1 AND F_score = 1 AND M_score = 1 THEN 'Champions'
            WHEN R_score <= 2 AND F_score <= 2              THEN 'Loyal'
            WHEN R_score = 1 AND F_score >= 3               THEN 'Promising'
            WHEN R_score >= 3 AND F_score <= 2              THEN 'At Risk'
            WHEN R_score = 4 AND F_score >= 3               THEN 'Lost'
            ELSE 'Others'
        END AS rfm_label
    FROM rfm_score
)

SELECT 
		rfm_label,
		COUNT(customer_id) AS number_of_customer,
		ROUND(SUM(total_sales),2) AS total_sales,
		ROUND(SUM(monetary),2) AS total_profit,
		ROUND(SUM(monetary)/SUM(SUM(monetary)) OVER() * 100,2) AS pct_of_profit,
		ROUND(SUM(total_sales)/SUM(SUM(total_sales)) OVER() * 100,2) AS pct_of_revenue
FROM rfm_labeled r
GROUP BY rfm_label
ORDER BY
    CASE rfm_label
        WHEN 'Champions' THEN 1 
        WHEN 'Loyal'     THEN 2
        WHEN 'Promising' THEN 3
        WHEN 'At Risk'   THEN 4
        WHEN 'Lost'      THEN 5
        ELSE 6
    END;

-- Q10: For Corporate customers, which category combinations are bought together — and do multi-category buyers have meaningfully higher LTV?
WITH corp_cust AS (
    SELECT es.customer_id, es.order_date, p.category
    FROM e_commerce.ecom_sales es
    INNER JOIN e_commerce.product p ON es.product_code = p.product_code
    WHERE es.segment = 'Corporate'
),
first_category AS (
    SELECT DISTINCT customer_id,
        FIRST_VALUE(category) OVER (PARTITION BY customer_id ORDER BY order_date) AS first_bought
    FROM corp_cust
),
category_breadth AS (
    SELECT customer_id, COUNT(DISTINCT category) AS number_of_category
    FROM corp_cust
    GROUP BY customer_id
),
customer_ltv AS (
    SELECT customer_id, SUM(profit) AS LTV
    FROM e_commerce.ecom_sales
    WHERE segment = 'Corporate'
    GROUP BY customer_id
),
category_pairs AS (
    SELECT a.customer_id, a.category AS category_a, b.category AS category_b
    FROM (SELECT DISTINCT customer_id, category FROM corp_cust) a
    INNER JOIN (SELECT DISTINCT customer_id, category FROM corp_cust) b
        ON  a.customer_id = b.customer_id
        AND a.category < b.category
)
-- LTV Lift by number of category 
SELECT
    cb.number_of_category,
    COUNT(DISTINCT cl.customer_id)  AS customer_count,
    ROUND(AVG(cl.LTV), 2)           AS avg_ltv
FROM category_breadth cb
INNER JOIN customer_ltv cl ON cl.customer_id = cb.customer_id
GROUP BY cb.number_of_category
ORDER BY cb.number_of_category;

-- LTV per customer
SELECT
    ca.customer_id,
    f.first_bought,
    ca.category_a,
    ca.category_b,
    cu.LTV
FROM category_pairs ca
INNER JOIN first_category f  ON f.customer_id = ca.customer_id
INNER JOIN customer_ltv cu   ON cu.customer_id = ca.customer_id;
