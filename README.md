# 🛒 Superstore Retail Sales Analysis

> End-to-end SQL data warehouse project — from messy raw CSV to a clean star schema with 15 business analyses.

![SQL Server](https://img.shields.io/badge/SQL%20Server-T--SQL-CC2927?style=flat-square&logo=microsoftsqlserver&logoColor=white)
![Architecture](https://img.shields.io/badge/Architecture-Medallion%20%28Bronze%20→%20Silver%20→%20Gold%29-F5A623?style=flat-square)
![Rows](https://img.shields.io/badge/Dataset-13%2C194%20rows-4CAF50?style=flat-square)
![Status](https://img.shields.io/badge/Status-Completed-brightgreen?style=flat-square)

---

## 📑 Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Dataset & Data Quality Issues](#dataset--data-quality-issues)
- [ETL Pipeline](#etl-pipeline)
- [Star Schema](#star-schema)
- [Analysis Sections](#analysis-sections)
- [Key Findings](#key-findings)
- [Project Files](#project-files)
- [How to Run](#how-to-run)
- [Validation Checks](#validation-checks)

---

## Project Overview

This project builds a complete **data warehouse** on top of the Superstore retail dataset using **MS SQL Server** and **T-SQL**. It follows the **Medallion Architecture** pattern (Bronze → Silver → Gold) to ingest raw messy data, clean and transform it, model it into a star schema, and run 15 analytical queries covering business KPIs, growth analysis, customer segmentation, churn, Pareto, and RFM scoring.

| Metric | Value |
|---|---|
| Raw rows ingested | 13,194 |
| Rows after cleaning | 9,986 |
| Duplicates removed | 3,208 |
| Unique orders | 5,008 |
| Unique customers | 793 |
| Unique products | 1,862 |
| Date range | 2014 – 2017 |
| Total sales | $2,458,300 |
| Total profit | $285,860 |
| Profit margin | 11.63% |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    superstoreDW Database                    │
├──────────────┬──────────────────────┬───────────────────────┤
│   BRONZE     │       SILVER         │         GOLD          │
│  Raw layer   │   Cleaned layer      │    Business layer     │
│              │                      │                       │
│  13,194 rows │    9,986 rows        │  Star Schema          │
│  All NVARCHAR│  Correct types       │  dim_customer  (793)  │
│  Nulls       │  Nulls fixed         │  dim_product  (1862)  │
│  Duplicates  │  Deduped             │  dim_geography (631)  │
│  Typos       │  Typos fixed         │  dim_date     (1237)  │
│  Bad casing  │  Casing normalized   │  fact_sales   (9986)  │
└──────────────┴──────────────────────┴───────────────────────┘
```

---

## Dataset & Data Quality Issues

The raw CSV (`Superstore_Messy_Data.csv`) contained **5 categories of data quality issues** that were identified and fixed in the Silver layer:

| # | Issue | Rows Affected | Fix Applied |
|---|---|---|---|
| 1 | Wrong data types (all imported as `NVARCHAR`) | All columns | `ALTER COLUMN` to correct types |
| 2 | `NULL` in `Customer_Name` | 401 rows | Replaced with `'Unknown'` |
| 3 | Inconsistent `City`/`State` casing (`NEW YORK`, `new york`, `New York`) | Many | Double-pass `UPPER(LEFT()) + LOWER(SUBSTRING())` |
| 4 | `City = 'NONE'` or empty string | 407 rows | Replaced with `'Unknown'` |
| 5 | `Order_ID` stored in `State` column by mistake | 1 row | Corrected to `'Arkansas'` |
| 6 | Typos in `Category` column | 1,275 rows | `'Technlogy'` → `'Technology'`, `'Furnture'` → `'Furniture'` |
| 7 | Duplicate records (same `Order_ID` + `Product_ID`) | 3,208 rows | Removed via `ROW_NUMBER()` CTE, kept earliest |

> ⚠️ **Key insight on the double casing pass:** The casing normalization runs twice intentionally. The first pass normalizes all rows; the second pass re-runs after the State data-entry error is corrected, ensuring the fixed Arkansas row also gets consistent casing. Skipping the second pass causes 6 extra rows in `dim_geography` (632 vs 626) due to residual casing mismatches in multi-word city names like `Los Angeles`.

---

## ETL Pipeline

The pipeline is executed in **6 sequential steps** inside `SP_DW_Pipeline.sql`:

```
Step 1 — Database & Schema Setup
         CREATE DATABASE superstoreDW
         CREATE SCHEMA bronze | silver | gold

Step 2 — Bronze Layer
         Import CSV as-is via SSMS Import Flat File wizard
         No transformations — raw data preserved exactly

Step 3 — Silver Layer (Data Cleaning)
         3a  Fix data types
         3b  Fix NULL Customer_Name (401 rows)
         3c  Fix City/State casing + data entry error (double pass)
         3d  Fix Category typos (1,275 rows)
         3e  Remove duplicates via ROW_NUMBER() CTE (3,208 rows)

Step 4 — Gold Layer (Star Schema)
         4a  dim_customer   — deduplicated by Customer_ID
         4b  dim_product    — canonical name per Product_ID
         4c  dim_geography  — built AFTER double casing pass
         4d  dim_date       — one row per unique Order_Date
         4e  fact_sales     — measures + surrogate FK keys

Step 5 — Constraints
         Primary Keys on all dimension tables
         Foreign Keys on fact_sales → all dimensions

Step 6 — Validation
         Row counts, sales totals, profit totals, NULL FK checks
```

---

## Star Schema

```
                    ┌─────────────────┐
                    │   dim_date      │
                    │─────────────────│
                    │ Order_Date (PK) │
                    │ Year            │
                    │ Month           │
                    └────────┬────────┘
                             │ FK
┌──────────────────┐    ┌────┴───────────────┐    ┌─────────────────┐
│   dim_customer   │    │    fact_sales       │    │   dim_product   │
│──────────────────│    │────────────────────│    │─────────────────│
│ Customer_ID (PK) │◄───┤ Customer_ID (FK)   │    │ Product_Key (PK)│
│ Customer_Name    │    │ Product_Key (FK)   ├───►│ Product_ID      │
│ Segment          │    │ Geo_Key (FK)        │    │ Product_Name    │
└──────────────────┘    │ Order_Date (FK)     │    │ Category        │
                        │────────────────────│    │ Sub_Category    │
┌──────────────────┐    │ Order_ID           │    └─────────────────┘
│  dim_geography   │    │ Sales              │
│──────────────────│    │ Quantity           │
│ Geo_Key (PK)     │◄───┤ Profit             │
│ City             │    │ Discount           │
│ State            │    └────────────────────┘
│ Region           │
│ Country          │
└──────────────────┘
```

---

## Analysis Sections

The `Superstore_Data_Analysis.sql` file contains **15 analytical queries** against the Gold layer:

| Section | Topic | Techniques Used |
|---|---|---|
| §1 | Business KPIs | `SUM`, `COUNT DISTINCT`, `ROUND` |
| §2 | Regional performance | Subquery, sales contribution % |
| §3 | Category performance | `GROUP BY`, `AVG`, `ORDER BY` |
| §4 | Segment-wise performance | Multi-measure aggregation |
| §5 | Year-over-year growth | `LAG()` window function |
| §6 | CAGR calculation | `POWER()`, nested subqueries |
| §7 | Peak season analysis | `DATENAME`, `RANK()`, CTEs |
| §8 | Repeat vs one-time customers | `CASE WHEN`, `COUNT DISTINCT` |
| §9 | Top 5% customers by revenue | `NTILE(100)`, percentile ranking |
| §10 | Running total of sales | `SUM() OVER (ROWS UNBOUNDED PRECEDING)` |
| §11 | Pareto analysis (80/20 rule) | Running sum, 80% threshold filter |
| §12 | Year-over-year customer churn | `LEFT JOIN` self-join by year |
| §13 | YoY profit margin by segment | `LAG()` partitioned by segment |
| §14 | RFM analysis | `DATEDIFF`, `NTILE(5)`, composite scoring |
| §15 | Sub-category profitability | `CASE WHEN` margin classification |

---

## Key Findings

### 💰 Business KPIs
| Metric | Value |
|---|---|
| Total Sales | $2,458,300 |
| Total Profit | $285,860 |
| Profit Margin | 11.63% |
| Average Order Value | $490.87 |
| CAGR (2014–2017) | **15.92%** |

---

### 🗺️ Regional Performance
| Region | Sales | Share | Margin |
|---|---|---|---|
| West | $786,410 | 32.0% | 13.8% |
| East | $726,301 | 29.5% | 12.6% |
| Central | $530,229 | 21.6% | 7.5% ⚠️ |
| South | $415,360 | 16.9% | 11.2% |

> Central region has the weakest margin at 7.5% despite contributing 21.6% of sales.

---

### 📦 Category Performance
| Category | Sales | Profit | Avg Profit/Order |
|---|---|---|---|
| Technology | $898,182 | $145,368 | $78.79 |
| Furniture | $818,654 | $18,380 | $8.67 ⚠️ |
| Office Supplies | $741,464 | $122,112 | $20.28 |

> Furniture generates nearly as much sales as Technology but only 12% of the profit.

---

### 📈 Year-over-Year Growth
| Year | Sales | Profit | Sales Growth | Profit Growth |
|---|---|---|---|---|
| 2014 | $500,872 | $49,556 | — | — |
| 2015 | $508,688 | $61,556 | +1.56% | +24.22% |
| 2016 | $668,612 | $81,477 | **+31.44%** | +32.36% |
| 2017 | $780,128 | $93,271 | +16.68% | +14.48% |

---

### 🗓️ Peak Season
November, September, and December appeared in the **top 4 revenue months every single year** (4 of 4).

| Month | Peak Frequency | Avg Peak Sales |
|---|---|---|
| November | 4 / 4 ⭐ | $95,320 |
| September | 4 / 4 ⭐ | $87,914 |
| December | 4 / 4 ⭐ | $83,012 |

---

### 👥 Customer Segmentation
| Type | Count | % of Total |
|---|---|---|
| Loyal Buyer (5+ orders) | 598 | 75.41% |
| Occasional Buyer (2–4 orders) | 183 | 23.08% |
| One-Time Buyer | 12 | 1.51% |

---

### 📉 Customer Churn (YoY)
| Year | Total | Retained | Churned | Churn Rate |
|---|---|---|---|---|
| 2014 | 595 | 437 | 158 | 26.55% |
| 2015 | 573 | 452 | 121 | 21.12% |
| 2016 | 638 | 558 | 80 | **12.54%** ✅ |

> Churn improved by more than half over 3 years — strong retention trend.

---

### 🔴 Loss-Making Sub-Categories
| Sub-Category | Sales | Profit | Margin |
|---|---|---|---|
| Tables | $239,453 | −$17,725 | −7.4% |
| Bookcases | $125,629 | −$3,473 | −2.8% |
| Supplies | $46,816 | −$1,189 | −2.5% |

> Tables is the most damaging — $239K in sales that result in a net loss. Discount strategy or pricing needs review.

---

## Project Files

```
📁 superstore-dw/
├── Superstore_Messy_Data.csv       # Raw source dataset (13,194 rows, 21 columns)
├── SP_DW_Pipeline.sql              # Full ETL pipeline: Bronze → Silver → Gold
└── Superstore_Data_Analysis.sql    # 15 analytical queries against gold schema
```

---

## How to Run

**Prerequisites:** Microsoft SQL Server (2016+) · SSMS

```sql
-- Step 1: Run Step 1 of SP_DW_Pipeline.sql to create the database and schemas
-- Step 2: Import Superstore_Messy_Data.csv into bronze schema via SSMS:
--         Right-click superstoreDW → Tasks → Import Flat File
--         Set destination schema to [bronze]
-- Step 3: Run Steps 3–6 of SP_DW_Pipeline.sql sequentially
-- Step 4: Run Superstore_Data_Analysis.sql against the gold schema
```

> ⚠️ Do not drop and recreate the database without re-importing the CSV first — the Bronze layer depends on the flat file import being present.

---

## Validation Checks

All validation checks in Step 6 pass with the following expected values:

| Check | Expected |
|---|---|
| `silver.Superstore_cleansed` rows | 9,986 |
| `gold.fact_sales` rows | 9,986 |
| Silver total sales | $2,347,314.26 |
| Fact total sales | $2,347,314.26 |
| Silver total profit | $286,025.36 |
| NULL `Geo_Key` in fact | 0 |
| NULL `Product_Key` in fact | 0 |
| NULL `Customer_ID` in fact | 0 |
| `dim_customer` rows | 793 |
| `dim_product` rows | 1,862 |
| `dim_geography` rows | 631 |
| `dim_date` rows | 1,237 |

---

*Author: Sarfraj Alam · Database: MS SQL Server · Pattern: Medallion Architecture*
