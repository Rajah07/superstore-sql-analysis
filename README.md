# 🛒 Superstore Retail Sales Analysis — SQL Project

## 📌 Project Overview

This project performs an end-to-end business intelligence analysis on the **Superstore Retail Dataset** using T-SQL (SQL Server). The goal is to extract actionable insights across sales performance, customer behaviour, product profitability, and growth trends — simulating the type of analysis a Data Analyst would deliver in a real business environment.

The dataset contains **13K+ transactional records** spanning orders, customers, products, and geography. The data pipeline is built on a **Medallion Architecture** with three layers — Bronze, Silver, and Gold — before analysis is performed on the final Gold layer using a **star schema** across five tables.

---

## 🏗️ Data Architecture — Medallion Architecture

This project follows the **Medallion Architecture** (also called Multi-Hop Architecture), an industry-standard data engineering pattern used in modern data warehouses and lakehouses. It organizes data into three progressive layers, each improving the quality and structure of the data.

```
┌─────────────────────────────────────────────────────────────────┐
│                    MEDALLION ARCHITECTURE                       │
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐ │
│  │  🥉 BRONZE   │───▶│  🥈 SILVER   │───▶│     🥇 GOLD     │  │
│  │   Raw Layer  │     │ Clean Layer  │     │  Business Layer  │ │
│  └──────────────┘     └──────────────┘     └──────────────────┘ │
│   Load as-is from     Clean, dedupe,      Separate into small   │
│   source (CSV)        transform data      dimension tables +    │
│                                           fact table            │
└─────────────────────────────────────────────────────────────────┘
```

### 🥉 Bronze Layer — Raw Data Ingestion
The raw CSV data is loaded **as-is** directly into the Bronze schema with no transformations. This preserves the original source data exactly as received, including any nulls, duplicates, inconsistent formatting, and data type issues.

- Source: `Superstore_Messy_Data.csv` (13K+ rows)
- No cleaning or transformation applied
- Acts as the single source of truth / audit log
- Table: `bronze.Superstore_Messy_Data`

### 🥈 Silver Layer — Data Cleaning & Transformation
The Bronze data is cleaned and transformed before loading into the Silver schema. This layer produces a **reliable, consistent** dataset ready for analysis.

Cleaning steps performed:
- Removed duplicate records
- Standardized date formats (`Order Date`, `Ship Date`)
- Handled NULL and missing values
- Corrected data types (e.g., Sales and Profit as `FLOAT`, dates as `DATE`)
- Trimmed whitespace from string columns
- Validated referential integrity across columns

- Table: `silver.Superstore_cleansed`

### 🥇 Gold Layer — Business-Ready Star Schema
The cleaned Silver data is **split into small, focused dimension tables** and one central fact table. This is the layer where all SQL analysis is performed.

| Table | Type | Contains |
|---|---|---|
| `gold.fact_sales` | Fact Table | Orders, Sales, Profit, Discount, Quantity, foreign keys |
| `gold.dim_customer` | Dimension | Customer ID, Name, Segment |
| `gold.dim_product` | Dimension | Product ID, Name, Category, Sub-Category |
| `gold.dim_geography` | Dimension | Region, City, State, Postal Code |
| `gold.dim_date` | Dimension | Date, Year, Month, Quarter (date intelligence) |

**Why star schema?** By separating data into one fact table and multiple dimension tables, queries become faster, joins are simpler, and the model scales well for reporting tools like Power BI.

### Why Medallion Architecture?

| Benefit | Explanation |
|---|---|
| **Data traceability** | Raw data is never overwritten — always available in Bronze for debugging |
| **Separation of concerns** | Cleaning logic lives in Silver; business logic lives in Gold |
| **Industry standard** | Used by companies like Microsoft, Databricks, and most modern data teams |
| **Scalable** | New data sources can be added at Bronze without affecting downstream layers |

---

## 🗂️ Dataset Schema

| Table | Type | Description |
|---|---|---|
| `gold.fact_sales` | Fact | Core transactional data — orders, sales, profit, discount, quantity |
| `gold.dim_customer` | Dimension | Customer ID, name, segment (Consumer, Corporate, Home Office) |
| `gold.dim_product` | Dimension | Product ID, name, category, sub-category |
| `gold.dim_geography` | Dimension | Region, city, state, postal code |
| `gold.dim_date` | Dimension | Date attributes — year, month, quarter for time-based analysis |

---

## 🎯 Business Questions Answered

1. What are the overall KPIs — total revenue, profit, and average order value?
2. Which regions contribute the most to sales and profit?
3. Which product categories and sub-categories are most/least profitable?
4. How has sales and profit grown year over year?
5. What is the Compound Annual Growth Rate (CAGR) of the business?
6. Which months are peak sales seasons?
7. What percentage of customers and products drive 80% of revenue? (Pareto)
8. How many customers churn each year, and what is the churn rate?
9. Who are the top 5% highest-value customers?
10. How can customers be segmented using RFM scoring?

---

## 📊 Analysis Sections

### Section 1 — Business KPIs
Calculated the four headline metrics every business tracks: **Total Sales**, **Total Profit**, **Profit Margin %**, and **Average Order Value (AOV)** using aggregate functions across all transactions.

```sql
SELECT
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit) * 100.0 / SUM(sales), 2) AS profit_margin_pct,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2) AS avg_order_value
FROM gold.fact_sales;
```

---

### Section 2 — Regional Performance
Joined `fact_sales` with `dim_geography` to calculate **sales contribution %** and **profit margin** per region. Used a subquery to compute the total sales baseline for percentage calculations.

**Key insight:** Identifies which regions are high-revenue but low-margin — a critical input for regional budget allocation.

---

### Section 3 — Category Performance
Grouped sales and profit by product category, calculating total orders, total revenue, and **average profit per category**. Helps identify which categories contribute most to the bottom line.

---

### Section 4 — Segment-Wise Performance
Broke down sales, profit, margin, and customer count by **customer segment** (Consumer, Corporate, Home Office). Useful for understanding which segment is most valuable and which needs growth attention.

---

### Section 5 — Year-over-Year Growth
Used the **`LAG()` window function** to compare each year's sales and profit against the previous year, computing **YoY growth %** for both metrics.

```sql
ROUND(100.0 * (total_sales - LAG(total_sales) OVER (ORDER BY yr))
            / LAG(total_sales) OVER (ORDER BY yr), 2) AS sales_growth_pct
```

**Technique:** `LAG()` retrieves the value from the previous row in the ordered result set — ideal for period-over-period comparisons without a self-join.

---

### Section 6 — CAGR (Compound Annual Growth Rate)
Computed the **CAGR** of the business using first-year and latest-year sales, and the time period in years. Uses scalar subqueries nested inside a derived table.

**Formula:** `CAGR = (Latest Year Sales / First Year Sales) ^ (1/t) - 1`

CAGR gives a single smoothed annual growth rate, removing year-to-year volatility — commonly used in business performance reports.

---

### Section 7 — Peak Season Analysis
Identified the **top 4 revenue months per year** using a **multi-level CTE** with `RANK()` partitioned by year, then aggregated across years to find which months most frequently appear as peak sales months.

```sql
RANK() OVER (PARTITION BY yr ORDER BY monthly_sales DESC) AS rnk
```

**Output:** A ranked list of months by how often they appear in the top 4, helping with demand planning and inventory strategy.

---

### Section 8 — Repeat vs One-Time Customers
Classified every customer into **One-Time Buyer**, **Occasional Buyer**, or **Loyal Buyer** based on their total order count, using a `CASE` expression with percentage-of-total calculated via `SUM() OVER()`.

**Business value:** Understanding purchase frequency distribution helps retention teams prioritize which customer tier to target.

---

### Section 9 — Top 5% Customers by Revenue
Used **`NTILE(100)`** to divide customers into 100 percentile buckets by total spend, then filtered the top 5 percentiles and joined with `dim_customer` to retrieve customer names.

**Technique:** `NTILE()` is a distribution window function — cleaner than a self-join percentile approach and scales well on large datasets.

---

### Section 10 — Running Total of Sales Within Category
Computed a **cumulative running total of sales** per product category ordered by date, using a bounded window frame:

```sql
SUM(f.sales) OVER (
    PARTITION BY p.category
    ORDER BY f.order_date, f.order_id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
```

This is used in trend analysis to see how sales accumulate over time within each product line.

---

### Section 11 — Pareto Analysis (80/20 Rule)
Answered: **"What % of customers drive 80% of revenue?"** and repeated for products.

Used `SUM() OVER (ORDER BY ...)` to build a running total, then filtered where the running total was ≤ 80% of total sales, and calculated what fraction of total customers/products that represents.

**Why it matters:** In most retail businesses, a small minority of customers and products drive the majority of revenue. Pareto analysis quantifies this and guides where to focus retention and marketing effort.

---

### Section 12 — Year-over-Year Customer Churn
Built a **churn model using a self-join** — identified customers present in year N who did NOT appear in year N+1, labelling them as churned.

```sql
LEFT JOIN (...) t2
    ON t1.customer_id = t2.repeated_id
    AND t1.current_yr  = t2.next_yr - 1
```

Calculated churned customers, retained customers, and **churn rate %** for each year. Excluded the final year (no "next year" to compare against).

---

### Section 13 — YoY Profit Margin by Segment
Combined `GROUP BY` with `LAG()` partitioned by segment to track how **profit margins evolved year-over-year for each customer segment**. Helps detect if a segment is becoming less profitable over time.

---

### Section 14 — RFM Analysis
Built a full **RFM (Recency, Frequency, Monetary) customer scoring model**:

| Dimension | Definition | Scoring |
|---|---|---|
| **Recency** | Days since last purchase | Lower = better (score 5) |
| **Frequency** | Number of distinct orders | Higher = better (score 5) |
| **Monetary** | Total revenue generated | Higher = better (score 5) |

Used `NTILE(5)` to score each customer 1–5 on all three dimensions, then summed scores and applied a segment label (Champion, Loyal Customer, Recent Customer, At-Risk Loyal, Needs Attention).

**Why RFM:** It is the most widely used customer segmentation model in retail analytics, enabling targeted marketing, re-engagement campaigns, and VIP identification.

---

### Section 15 — Sub-Category Profitability Deep Dive
Analysed profit margin at the **sub-category level** and labelled each as Loss-Making, Low Margin, Moderate Margin, or High Margin using a `CASE` expression.

**Key insight:** Some sub-categories may have high sales volume but negative profit — important for pricing and product discontinuation decisions.

---

## 🛠️ SQL Techniques Used

| Technique | Used In |
|---|---|
| Aggregate Functions (`SUM`, `AVG`, `COUNT`) | Sections 1, 2, 3, 4 |
| Window Functions (`LAG`, `RANK`, `NTILE`, `SUM OVER`) | Sections 5, 7, 9, 10, 11, 13, 14 |
| Common Table Expressions (CTEs) | Sections 5, 7, 8, 9, 11, 12, 14 |
| Multi-table JOINs (Star Schema) | Sections 2, 3, 4, 9, 10, 13, 14, 15 |
| Subqueries (Scalar & Correlated) | Sections 2, 6, 11, 12 |
| Self-Join | Section 12 |
| CASE Expressions | Sections 8, 14, 15 |
| Date Functions (`YEAR`, `DATEDIFF`, `DATENAME`, `EOMONTH`) | Sections 5, 6, 7, 12, 13, 14 |
| `FORMAT` for percentage display | Sections 8, 11, 12 |
| `POWER` for CAGR formula | Section 6 |

---

## 📁 Repository Structure

```
superstore-sql-analysis/
├── Superstore_Data_Analysis.sql    # Full SQL analysis (15 sections)
├── Superstore_Messy_Data.csv       # Raw dataset (13,000+ rows)
└── README.md                       # Project documentation
```

---

## 💡 Key Business Insights (Summary)

- A small subset of customers and products follow the **80/20 rule** — most revenue is concentrated in a minority
- **Churn analysis** reveals year-wise customer retention health, enabling proactive re-engagement
- **CAGR** provides a single growth metric that smooths annual volatility
- **RFM scoring** segments customers into actionable tiers for targeted marketing
- Some sub-categories are **loss-making** despite high order volumes — highlighting pricing inefficiencies

---

## 👤 Author

**Sarfraj Alam**
📧 sarfraj7306@gmail.com
🔗 [LinkedIn](https://linkedin.com/in/sarfraj-alam07) | [GitHub](https://github.com/Rajah07)

