/* ============================================================
   PROJECT  : Superstore Retail Sales Analysis
   AUTHOR   : Sarfraj Alam
   DATABASE : SQL Server (T-SQL)
   DATASET  : Superstore Sales (13K+ transactions)
   SCHEMA   : gold.fact_sales | gold.dim_geography
              gold.dim_product | gold.dim_customer
   TOPICS   : KPIs, Growth Analysis, Seasonality,
              Segmentation, Churn, Pareto, RFM
   ============================================================ */


/* ============================================================
   SECTION 1 — BUSINESS KPIs
   Total Sales | Total Profit | Profit Margin | AOV
   ============================================================ */

SELECT
    ROUND(SUM(sales), 2)                                    AS total_sales,
    ROUND(SUM(profit), 2)                                   AS total_profit,
    FORMAT(SUM(profit) / SUM(sales), 'P')             AS profit_margin_pct,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2)         AS avg_order_value
FROM gold.fact_sales;


/* ============================================================
   SECTION 2 — REGIONAL PERFORMANCE
   Sales contribution % and profit margin by region
   ============================================================ */

SELECT
    region,
    sales_by_region,
    profit_by_region,
    total_sales,
    FORMAT(sales_by_region / total_sales, 'P')      AS sales_contribution_pct,
    FORMAT(profit_by_region / sales_by_region, 'P') AS profit_margin_pct
FROM (
    SELECT
        g.region,
        ROUND(SUM(f.sales), 2)                              AS sales_by_region,
        ROUND(SUM(f.profit), 2)                             AS profit_by_region,
        ROUND((SELECT SUM(sales) FROM gold.fact_sales), 2)  AS total_sales
    FROM gold.fact_sales f
    JOIN gold.dim_geography g ON g.geo_key = f.geo_key
    GROUP BY g.region
) t;


/* ============================================================
   SECTION 3 — CATEGORY PERFORMANCE
   Average profit per product category
   ============================================================ */

SELECT
    p.category,
    ROUND(AVG(f.profit), 2)     AS avg_profit,
    ROUND(SUM(f.profit), 2)     AS total_profit,
    ROUND(SUM(f.sales), 2)      AS total_sales,
    COUNT(DISTINCT f.order_id)  AS total_orders
FROM gold.fact_sales f
JOIN gold.dim_product p ON p.product_key = f.product_key
GROUP BY p.category
ORDER BY total_sales DESC;


/* ============================================================
   SECTION 4 — SEGMENT-WISE PERFORMANCE
   Sales, profit, and margin broken down by customer segment
   ============================================================ */

SELECT
    c.segment,
    ROUND(SUM(f.sales), 2)                              AS total_sales,
    ROUND(SUM(f.profit), 2)                             AS total_profit,
    FORMAT(SUM(f.profit) / SUM(f.sales), 'P')           AS profit_margin_pct,
    COUNT(DISTINCT f.order_id)                          AS total_orders,
    COUNT(DISTINCT f.customer_id)                       AS total_customers
FROM gold.fact_sales f
JOIN gold.dim_customer c ON c.Customer_ID = f.customer_ID
GROUP BY c.segment
ORDER BY total_sales DESC;


/* ============================================================
   SECTION 5 — YEAR-OVER-YEAR GROWTH
   Sales and profit growth % compared to previous year
   ============================================================ */

WITH yearly_metrics AS (
    SELECT
        YEAR(order_date)        AS yr,
        SUM(sales)              AS total_sales,
        SUM(profit)             AS total_profit
    FROM gold.fact_sales
    GROUP BY YEAR(order_date)
)
SELECT
    yr,
    ROUND(total_sales, 2)                                                               AS total_sales,
    ROUND(total_profit, 2)                                                              AS total_profit,
    ROUND(LAG(total_sales)  OVER (ORDER BY yr), 2)                                      AS prev_yr_sales,
    ROUND(LAG(total_profit) OVER (ORDER BY yr), 2)                                      AS prev_yr_profit,
    FORMAT((total_sales  - LAG(total_sales)  OVER (ORDER BY yr))
                / LAG(total_sales)  OVER (ORDER BY yr), 'P')                              AS sales_growth_pct,
    FORMAT((total_profit - LAG(total_profit) OVER (ORDER BY yr))
                / LAG(total_profit) OVER (ORDER BY yr), 'P')                              AS profit_growth_pct
FROM yearly_metrics
ORDER BY yr;


/* ============================================================
   SECTION 6 — CAGR (Compound Annual Growth Rate)
   Formula: (Latest Year Sales / First Year Sales) ^ (1/t) - 1
   t = number of years between first and last year
   ============================================================ */

SELECT
    FORMAT(
        (POWER(latest_yr_sale * 1.0 / first_yr_sale, 1.0 / t) - 1),
    'P') AS cagr_pct
FROM (
    SELECT
        (SELECT MAX(YEAR(order_date)) - MIN(YEAR(order_date)) FROM gold.fact_sales)  AS t,
        (
            SELECT SUM(sales)
            FROM gold.fact_sales
            WHERE YEAR(order_date) = (SELECT MIN(YEAR(order_date)) FROM gold.fact_sales)
        ) AS first_yr_sale,
        (
            SELECT SUM(sales)
            FROM gold.fact_sales
            WHERE YEAR(order_date) = (SELECT MAX(YEAR(order_date)) FROM gold.fact_sales)
        ) AS latest_yr_sale
) AS final_data;


/* ============================================================
   SECTION 7 — PEAK SEASON ANALYSIS
   Top 4 sales months per year → most frequent peak months
   ============================================================ */

WITH monthly_sales AS (
    SELECT
        YEAR(order_date)                AS yr,
        DATENAME(MONTH, order_date)     AS month_name,
        EOMONTH(order_date)             AS month_end,
        ROUND(SUM(sales), 2)            AS monthly_sales
    FROM gold.fact_sales
    GROUP BY YEAR(order_date), DATENAME(MONTH, order_date), EOMONTH(order_date)
),
ranked AS (
    SELECT *,
        RANK() OVER (PARTITION BY yr ORDER BY monthly_sales DESC) AS rnk
    FROM monthly_sales
),
top_months AS (
    SELECT * FROM ranked WHERE rnk <= 4
)
SELECT
    month_name,
    COUNT(*)    AS peak_frequency,
    ROUND(AVG(monthly_sales), 2) AS avg_peak_sales
FROM top_months
GROUP BY month_name
ORDER BY peak_frequency DESC, avg_peak_sales DESC;


/* ============================================================
   SECTION 8 — REPEAT vs ONE-TIME CUSTOMERS
   Classify customers by purchase frequency
   ============================================================ */

WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders
    FROM gold.fact_sales
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN total_orders = 1 THEN 'One-Time Buyer'
        WHEN total_orders BETWEEN 2 AND 4 THEN 'Occasional Buyer'
        ELSE 'Loyal Buyer'
    END                                 AS customer_type,
    COUNT(*)                            AS customer_count,
    FORMAT(COUNT(*)
        / SUM(COUNT(*)) OVER (), 'P')     AS pct_of_total
FROM customer_orders
GROUP BY
    CASE
        WHEN total_orders = 1 THEN 'One-Time Buyer'
        WHEN total_orders BETWEEN 2 AND 4 THEN 'Occasional Buyer'
        ELSE 'Loyal Buyer'
    END
ORDER BY customer_count DESC;


/* ============================================================
   SECTION 9 — TOP 5% CUSTOMERS BY REVENUE
   Identify high-value customers using NTILE()
   ============================================================ */

WITH customer_sales AS (
    SELECT
        customer_id,
        ROUND(SUM(sales), 2) AS total_spent
    FROM gold.fact_sales
    GROUP BY customer_id
),
percentiles AS (
    SELECT *,
        NTILE(100) OVER (ORDER BY total_spent DESC) AS percentile_rank
    FROM customer_sales
)
SELECT
    c.customer_id,
    c.customer_name,
    p.total_spent,
    p.percentile_rank
FROM percentiles p
JOIN gold.dim_customer c ON c.customer_id = p.customer_id
WHERE p.percentile_rank <= 5
ORDER BY p.total_spent DESC;


/* ============================================================
   SECTION 10 — RUNNING TOTAL OF SALES WITHIN CATEGORY
   Cumulative sales progression per product category
   ============================================================ */

SELECT
    p.category,
    f.order_date,
    f.order_id,
    ROUND(f.sales, 2)                                       AS order_sales,
    ROUND(SUM(f.sales) OVER (
        PARTITION BY p.category
        ORDER BY f.order_date, f.order_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2)                                                   AS running_total_sales
FROM gold.fact_sales f
JOIN gold.dim_product p ON p.product_key = f.product_key
ORDER BY p.category, f.order_date;


/* ============================================================
   SECTION 11 — PARETO ANALYSIS (80/20 Rule)
   What % of customers drive 80% of total revenue?
   ============================================================ */

-- By Customer
SELECT
    FORMAT(cnt * 1.0 / tot_customers, 'P') AS customer_pct_driving_80_pct_revenue
FROM (
    SELECT
        COUNT(*)                                AS cnt,
        (SELECT COUNT(*) FROM gold.dim_customer) AS tot_customers
    FROM (
        SELECT
            customer_id,
            sale_per_cust,
            SUM(sale_per_cust) OVER ()                              AS total_sales,
            SUM(sale_per_cust) OVER (ORDER BY sale_per_cust DESC)   AS running_total
        FROM (
            SELECT customer_id, SUM(sales) AS sale_per_cust
            FROM gold.fact_sales
            GROUP BY customer_id
        ) t
    ) t1
    WHERE running_total <= 0.8 * total_sales
) t2;

-- By Product
SELECT
    FORMAT(cnt * 1.0 / tot_products, 'P') AS product_pct_driving_80_pct_revenue
FROM (
    SELECT
        COUNT(*)                                 AS cnt,
        (SELECT COUNT(*) FROM gold.dim_product)  AS tot_products
    FROM (
        SELECT
            product_id,
            sale_per_product,
            SUM(sale_per_product) OVER ()                               AS total_sales,
            SUM(sale_per_product) OVER (ORDER BY sale_per_product DESC) AS running_total
        FROM (
            SELECT product_id, SUM(sales) AS sale_per_product
            FROM gold.fact_sales
            GROUP BY product_id
        ) t
    ) t1
    WHERE running_total <= 0.8 * total_sales
) t2;


/* ============================================================
   SECTION 12 — YEAR-OVER-YEAR CUSTOMER CHURN
   Customers who did NOT return the following year
   ============================================================ */

SELECT
    current_yr,
    COUNT(customer_id)          AS total_customers,
    COUNT(repeated_id)          AS retained_customers,
    COUNT(customer_id)
        - COUNT(repeated_id)    AS churned_customers,
    FORMAT(
        (COUNT(customer_id) - COUNT(repeated_id)) * 1.0
        / COUNT(customer_id), 'P'
    )                           AS churn_rate
FROM (
    SELECT
        t1.customer_id,
        t1.current_yr,
        t2.repeated_id
    FROM (
        SELECT DISTINCT customer_id, YEAR(order_date) AS current_yr
        FROM gold.fact_sales
    ) t1
    LEFT JOIN (
        SELECT DISTINCT customer_id AS repeated_id, YEAR(order_date) AS next_yr
        FROM gold.fact_sales
    ) t2
        ON t1.customer_id = t2.repeated_id
        AND t1.current_yr  = t2.next_yr - 1
) t3
WHERE current_yr <> (SELECT MAX(YEAR(order_date)) FROM gold.fact_sales)
GROUP BY current_yr
ORDER BY current_yr;


/* ============================================================
   SECTION 13 — YoY PROFIT MARGIN BY SEGMENT
   Track margin trends per customer segment across years
   ============================================================ */

SELECT
    YEAR(f.order_date)                                      AS yr,
    c.segment,
    ROUND(SUM(f.sales), 2)                                  AS total_sales,
    ROUND(SUM(f.profit), 2)                                 AS total_profit,
    FORMAT(SUM(f.profit) / SUM(f.sales), 'P')         AS profit_margin_pct,
    FORMAT(
        LAG(SUM(f.profit) / SUM(f.sales))
            OVER (PARTITION BY c.segment ORDER BY YEAR(f.order_date)),
    'P')                                                      AS prev_yr_margin_pct
FROM gold.fact_sales f
JOIN gold.dim_customer c ON c.Customer_ID = f.customer_ID
GROUP BY YEAR(f.order_date), c.segment
ORDER BY c.segment, yr;


/* ============================================================
   SECTION 14 — RFM ANALYSIS (Recency, Frequency, Monetary)
   Customer scoring model to identify best customers
   ============================================================ */

WITH rfm_base AS (
    SELECT
        customer_id,
        DATEDIFF(DAY, MAX(order_date),
            (SELECT MAX(order_date) FROM gold.fact_sales)) AS recency_days,
        COUNT(DISTINCT order_id)                            AS frequency,
        ROUND(SUM(sales), 2)                                AS monetary
    FROM gold.fact_sales
    GROUP BY customer_id
),
rfm_scores AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY recency_days ASC)   AS r_score,  -- lower recency = better
        NTILE(5) OVER (ORDER BY frequency DESC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC)      AS m_score
    FROM rfm_base
)
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    r_score + f_score + m_score                 AS rfm_total_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 THEN 'Champion'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customer'
        WHEN r_score >= 4 AND f_score < 3  THEN 'Recent Customer'
        WHEN r_score < 3  AND f_score >= 4 THEN 'At-Risk Loyal'
        ELSE 'Needs Attention'
    END                                         AS customer_segment
FROM rfm_scores
ORDER BY rfm_total_score DESC;


/* ============================================================
   SECTION 15 — SUB-CATEGORY PROFITABILITY DEEP DIVE
   Identify loss-making vs high-margin sub-categories
   ============================================================ */

SELECT
    p.category,
    p.sub_category,
    ROUND(SUM(f.sales), 2)                              AS total_sales,
    ROUND(SUM(f.profit), 2)                             AS total_profit,
    FORMAT(SUM(f.profit) / SUM(f.sales), 'P')           AS profit_margin_pct,
    COUNT(DISTINCT f.order_id)                          AS total_orders,
    CASE
        WHEN SUM(f.profit) < 0 THEN 'Loss-Making'
        WHEN SUM(f.profit) * 100.0 / SUM(f.sales) < 10 THEN 'Low Margin'
        WHEN SUM(f.profit) * 100.0 / SUM(f.sales) < 25 THEN 'Moderate Margin'
        ELSE 'High Margin'
    END                                                 AS margin_category
FROM gold.fact_sales f
JOIN gold.dim_product p ON p.product_key = f.product_key
GROUP BY p.category, p.sub_category
ORDER BY total_profit DESC;
