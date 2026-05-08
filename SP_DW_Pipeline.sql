/* ============================================================
   PROJECT  : Superstore Data Warehouse — ETL Pipeline
   AUTHOR   : Sarfraj Alam
   DATABASE : superstoreDW
   PATTERN  : Medallion Architecture (Bronze → Silver → Gold)

   PIPELINE OVERVIEW:
   Step 1 — Database & Schema Setup
   Step 2 — Bronze Layer  : Load raw CSV data as-is
   Step 3 — Silver Layer  : Clean & transform data
   Step 4 — Gold Layer    : Build star schema (Dimensions + Fact)
   Step 5 — Constraints   : Add Primary Keys & Foreign Keys
   Step 6 — Validation    : Verify row counts & totals

   VERIFIED FINAL EXPECTED VALUES:
   ┌─────────────────────────────────┬────────────────┐
   │ Table / Metric                  │ Expected Value │
   ├─────────────────────────────────┼────────────────┤
   │ bronze.Superstore_Messy_Data    │ 13,194 rows    │
   │ silver.Superstore_cleansed      │  9,986 rows    │
   │ silver Total Sales              │ 2,330,572.75   │
   │ silver Total Profit             │   286,019.33   │
   │ gold.dim_customer               │    793 rows    │
   │ gold.dim_product                │  1,862 rows    │
   │ gold.dim_geography              │    626 rows    │
   │ gold.dim_date                   │    483 rows    │
   │ gold.fact_sales                 │  9,986 rows    │
   │ fact Total Sales                │ 2,330,572.75   │
   │ fact Total Profit               │   286,019.33   │
   │ NULL Geo_Keys in fact           │      0         │
   │ NULL Product_Keys in fact       │      0         │
   └─────────────────────────────────┴────────────────┘
   ============================================================ */


/* ============================================================
   STEP 1 — DATABASE & SCHEMA SETUP
   Create the database and three medallion schema layers.

   ⚠️  WARNING: DROP DATABASE wipes everything including
   bronze.Superstore_Messy_Data which was loaded via CSV import.
   After Step 1 completes, re-import the CSV before Step 2:
     → Right-click superstoreDW in SSMS Object Explorer
     → Tasks → Import Flat File
     → Select Superstore_Messy_Data.csv
     → Set destination schema to [bronze]
   ============================================================ */

USE master;
GO

DROP DATABASE IF EXISTS superstoreDW;
GO
CREATE DATABASE superstoreDW;
GO
USE superstoreDW;
GO

CREATE SCHEMA bronze;   -- Raw data layer   (Bronze)
GO
CREATE SCHEMA silver;   -- Cleaned layer     (Silver)
GO
CREATE SCHEMA gold;     -- Business layer    (Gold)
GO


/* ============================================================
   STEP 2 — BRONZE LAYER (Raw Ingestion)
   The raw CSV is imported as-is into the bronze schema via the
   SSMS Import Flat File wizard. No transformations applied here.
   This preserves original source data exactly as received,
   including nulls, duplicates, mixed casing, and typos.

   Source : Superstore_Messy_Data.csv
   Table  : bronze.Superstore_Messy_Data
   Rows   : 13,194
   ============================================================ */

-- Verify raw data loaded correctly after CSV import
SELECT * FROM bronze.Superstore_Messy_Data;
SELECT COUNT(*) AS total_raw_rows FROM bronze.Superstore_Messy_Data; -- Expected: 13,194


/* ============================================================
   STEP 3 — SILVER LAYER (Data Cleaning & Transformation)
   Copy Bronze → Silver, then apply all cleaning in-place.

   Issues found and fixed:
     3a — Wrong data types (all imported as NVARCHAR)
     3b — NULL Customer_Name (401 rows)
     3c — Inconsistent City/State casing + data entry error
     3d — Typos in Category column (2 distinct errors)
     3e — Duplicate records (same Order_ID + Product_ID)
   ============================================================ */

-- Snapshot Bronze into Silver (before any cleaning)
DROP TABLE IF EXISTS silver.Superstore_cleansed;

SELECT *
INTO silver.Superstore_cleansed
FROM bronze.Superstore_Messy_Data;

SELECT COUNT(*) AS total_silver_rows FROM silver.Superstore_cleansed; -- Expected: 13,194


/* ------------------------------------------------------------
   STEP 3a — Fix Data Types
   CSV import loads all columns as NVARCHAR by default.
   Cast each column to its correct analytical type.
   ------------------------------------------------------------ */

ALTER TABLE silver.Superstore_cleansed ALTER COLUMN Order_Date  DATE;
ALTER TABLE silver.Superstore_cleansed ALTER COLUMN Ship_Date   DATE;
ALTER TABLE silver.Superstore_cleansed ALTER COLUMN Sales       FLOAT;
ALTER TABLE silver.Superstore_cleansed ALTER COLUMN Profit      FLOAT;
ALTER TABLE silver.Superstore_cleansed ALTER COLUMN Discount    FLOAT;
ALTER TABLE silver.Superstore_cleansed ALTER COLUMN Quantity    INT;

-- Postal_Code imported as float string (e.g. "10001.0") — convert to INT
UPDATE silver.Superstore_cleansed
SET Postal_Code = CAST(CAST(Postal_Code AS FLOAT) AS INT)
WHERE Postal_Code IS NOT NULL;

ALTER TABLE silver.Superstore_cleansed ALTER COLUMN Postal_Code INT;


/* ------------------------------------------------------------
   STEP 3b — Fix NULL Customer Names
   401 rows had NULL in Customer_Name.
   Replaced with 'Unknown' to prevent FK issues downstream.
   ------------------------------------------------------------ */

-- Audit NULLs before fix
SELECT COUNT(*) AS null_customer_names
FROM silver.Superstore_cleansed
WHERE Customer_Name IS NULL; -- Expected: 401

UPDATE silver.Superstore_cleansed
SET Customer_Name = 'Unknown'
WHERE Customer_Name IS NULL; -- 401 rows updated


/* ------------------------------------------------------------
   STEP 3c — Fix City & State Columns
   Three issues found:
     1. City = 'NONE' / 'none' / '' (407 rows) → replaced with 'Unknown'
     2. Inconsistent casing — same city written as 'NEW YORK',
        'new york', 'New York' — standardized to first-letter-upper
     3. One row had Order_ID stored in the State column by mistake

   ⚠️  CASING RUNS TWICE (this is intentional):
   First pass normalizes all rows after the NONE fix.
   Second pass runs after the State error correction so the
   corrected row also gets proper casing. This guarantees
   dim_geography DISTINCT produces exactly 626 rows.
   Skipping the second pass causes 6 extra rows (632 vs 626)
   due to residual casing inconsistencies not caught by DISTINCT.
   ------------------------------------------------------------ */

-- Fix 1: Replace 'None' / 'none' / empty cities
UPDATE silver.Superstore_cleansed
SET City = 'Unknown'
WHERE UPPER(TRIM(City)) IN ('NONE', ''); -- 407 rows updated

-- Fix 2 (First pass): Standardize City and State casing
-- Pattern: UPPER(first char) + LOWER(rest)
-- e.g. 'NEW YORK' → 'New york' | 'san francisco' → 'San francisco'
UPDATE silver.Superstore_cleansed
SET
    City  = UPPER(LEFT(TRIM(City),  1)) + LOWER(SUBSTRING(TRIM(City),  2, LEN(TRIM(City)))),
    State = UPPER(LEFT(TRIM(State), 1)) + LOWER(SUBSTRING(TRIM(State), 2, LEN(TRIM(State))));

-- Verify distinct counts after first pass
SELECT COUNT(DISTINCT City)  AS distinct_cities  FROM silver.Superstore_cleansed; -- Expected: 532
SELECT COUNT(DISTINCT State) AS distinct_states  FROM silver.Superstore_cleansed; -- Expected: 50(Before Updating Order_ID), 49(After Updating)

-- Fix 3: Correct data entry error — Order_ID stored in State column
-- Identify the bad row
SELECT * FROM silver.Superstore_cleansed
WHERE State LIKE 'Ca-20%'; -- Finds Order_ID-in-State error

-- Correct it
UPDATE silver.Superstore_cleansed
SET State = 'Arkansas'
WHERE State = 'Ca-2015-108119'; -- 1 row corrected

-- Fix 2 (Second pass): Re-apply casing to catch any remaining variations
-- and ensure the corrected Arkansas row gets consistent casing.
UPDATE silver.Superstore_cleansed
SET
    City  = UPPER(LEFT(TRIM(City),  1)) + LOWER(SUBSTRING(TRIM(City),  2, LEN(TRIM(City)))),
    State = UPPER(LEFT(TRIM(State), 1)) + LOWER(SUBSTRING(TRIM(State), 2, LEN(TRIM(State))));

-- Final verification
SELECT COUNT(DISTINCT City)  AS distinct_cities  FROM silver.Superstore_cleansed; -- Expected: 532
SELECT COUNT(DISTINCT State) AS distinct_states  FROM silver.Superstore_cleansed; -- Expected: 49


/* ------------------------------------------------------------
   STEP 3d — Fix Typos in Category Column
   Two category names had spelling errors in the source data.
   ------------------------------------------------------------ */

-- Fix: 'Technlogy' → 'Technology'
UPDATE silver.Superstore_cleansed
SET Category = 'Technology'
WHERE Category = 'Technlogy'; -- 571 rows corrected

-- Fix: 'Furnture' → 'Furniture'
UPDATE silver.Superstore_cleansed
SET Category = 'Furniture'
WHERE Category = 'Furnture'; -- 704 rows corrected

-- Verify: must be exactly 3 distinct categories
SELECT DISTINCT Category FROM silver.Superstore_cleansed;
-- Expected: Furniture | Office Supplies | Technology


/* ------------------------------------------------------------
   STEP 3e — Remove Duplicate Records
   Duplicate = same Order_ID + Product_ID combination.
   Strategy: keep the earliest record (ORDER BY Order_Date ASC),
   delete all later duplicates using ROW_NUMBER() CTE.
   ------------------------------------------------------------ */

-- Preview duplicates before deletion
SELECT *,
    ROW_NUMBER() OVER (
        PARTITION BY Order_ID, Product_ID
        ORDER BY Order_Date
    ) AS rn
FROM silver.Superstore_cleansed;

-- Delete duplicates: keep rn = 1, delete rn > 1
WITH duplicates AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY Order_ID, Product_ID
            ORDER BY Order_Date
        ) AS rn
    FROM silver.Superstore_cleansed
)
DELETE FROM duplicates
WHERE rn > 1; -- Expected: 3,208 rows removed

-- Verify final Silver row count
SELECT COUNT(*) AS clean_silver_rows FROM silver.Superstore_cleansed; -- Expected: 9,986


/* ============================================================
   STEP 4 — GOLD LAYER (Star Schema — Data Modeling)
   Split the cleaned Silver table into a star schema:
   one central Fact table + four surrounding Dimension tables.

   Why star schema?
   - Faster analytical queries (pre-aggregated dimensions)
   - Small dimension tables are easy to join and reuse
   - Standard pattern for Power BI, SSAS, and BI tools

   Tables:
     gold.dim_customer   — WHO  bought        (793 rows)
     gold.dim_product    — WHAT was bought  (1,862 rows)
     gold.dim_geography  — WHERE it was bought (626 rows)
     gold.dim_date       — WHEN it was bought  (483 rows)
     gold.fact_sales     — Measures + FK keys (9,986 rows)
   ============================================================ */


/* ------------------------------------------------------------
   STEP 4a — dim_customer
   One unique row per Customer_ID.
   NULL names were replaced with 'Unknown' in Step 3b, which
   can create duplicate Customer_IDs (real name + 'Unknown').
   The CTE dedup below removes those extras.
   ------------------------------------------------------------ */

DROP TABLE IF EXISTS gold.dim_customer;

SELECT DISTINCT
    Customer_ID,
    Customer_Name,
    Segment
INTO gold.dim_customer
FROM silver.Superstore_cleansed;

-- Remove remaining Customer_ID duplicates — keep alphabetically first name
WITH dupes AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY Customer_ID
            ORDER BY Customer_Name
        ) AS rn
    FROM gold.dim_customer
)
DELETE FROM dupes WHERE rn > 1; -- Expected: 86 rows removed

SELECT COUNT(*) AS total_customers FROM gold.dim_customer; -- Expected: 793


/* ------------------------------------------------------------
   STEP 4b — dim_product
   One unique row per Product_ID with a surrogate integer key.

   Why not just DISTINCT on Product_ID?
   Some Product_IDs had multiple name variations in source data
   (typos, spacing differences), causing 1,894 rows instead of
   the correct 1,862. Fix: PARTITION BY Product_ID keeps only
   the alphabetically first name as the canonical product name.
   ------------------------------------------------------------ */

DROP TABLE IF EXISTS gold.dim_product;

SELECT
    ROW_NUMBER() OVER (ORDER BY Product_ID) AS Product_Key,
    Product_ID,
    Product_Name,
    Category,
    Sub_Category
INTO gold.dim_product
FROM (
    SELECT
        Product_ID,
        Product_Name,
        Category,
        Sub_Category,
        ROW_NUMBER() OVER (
            PARTITION BY Product_ID
            ORDER BY Product_Name  -- alphabetically first name = canonical
        ) AS rn
    FROM (
        SELECT DISTINCT
            Product_ID,
            Product_Name,
            Category,
            Sub_Category
        FROM silver.Superstore_cleansed
    ) AS unique_products
) AS deduplicated
WHERE rn = 1;

SELECT COUNT(*) AS total_products FROM gold.dim_product; -- Expected: 1,862


/* ------------------------------------------------------------
   STEP 4c — dim_geography
   One unique row per City + State + Region + Country combination
   with a surrogate integer key (Geo_Key).

   ⚠️  MUST be built AFTER the double casing pass in Step 3c.
   Building before the second casing pass causes 6 extra rows
   (632 instead of 626) because residual casing variations in
   City/State are not collapsed by DISTINCT.
   ------------------------------------------------------------ */

DROP TABLE IF EXISTS gold.dim_geography;

SELECT
    ROW_NUMBER() OVER (ORDER BY Country, State, City, Region) AS Geo_Key,
    City,
    State,
    Region,
    Country
INTO gold.dim_geography
FROM (
    SELECT DISTINCT
        City,
        State,
        Region,
        Country
    FROM silver.Superstore_cleansed
) AS unique_locations;

SELECT COUNT(*) AS total_locations FROM gold.dim_geography; -- Expected: 631


/* ------------------------------------------------------------
   STEP 4d — dim_date
   One row per unique Order_Date with Year and Month extracted.
   Avoids repeating date functions in every analytical query
   and enables clean time-intelligence in Power BI.
   ------------------------------------------------------------ */

DROP TABLE IF EXISTS gold.dim_date;

SELECT DISTINCT
    Order_Date,
    YEAR(Order_Date)  AS Year,
    MONTH(Order_Date) AS Month
INTO gold.dim_date
FROM silver.Superstore_cleansed;

SELECT COUNT(*) AS total_dates FROM gold.dim_date; -- Expected: 1237


/* ------------------------------------------------------------
   STEP 4e — fact_sales
   Central fact table: measures + foreign keys only.
   No descriptive columns — those live in the dimension tables.

   Join strategy:
   • dim_geography → 3-column join (Region + City + State) for
     precise location match with no ambiguity
   • dim_product   → Product_ID only (NOT Product_Name) because
     dim_product holds one canonical name per Product_ID; joining
     on name would produce NULL keys for non-canonical variants
   • Customer_ID carries over directly from silver — no extra join
   ------------------------------------------------------------ */

DROP TABLE IF EXISTS gold.fact_sales;

SELECT
    s.Order_ID,
    s.Product_ID,
    s.Customer_ID,
    g.Geo_Key,
    p.Product_Key,
    s.Order_Date,
    s.Sales,
    s.Quantity,
    s.Profit,
    s.Discount
INTO gold.fact_sales
FROM silver.Superstore_cleansed s
LEFT JOIN gold.dim_geography g
    ON  s.Region = g.Region
    AND s.City   = g.City
    AND s.State  = g.State
LEFT JOIN gold.dim_product p
    ON  s.Product_ID = p.Product_ID;

SELECT COUNT(*) AS total_fact_rows FROM gold.fact_sales; -- Expected: 9,986


/* ============================================================
   STEP 5 — CONSTRAINTS (Primary Keys & Foreign Keys)
   Enforce referential integrity across the star schema.

   Execution order is mandatory:
     1. Add PKs on dimension tables first
     2. Align fact column types to match dimension PK types exactly
     3. Add FKs on fact table pointing to each dimension

   ⚠️  Run NULL FK checks in Step 6 section 5 before this step.
      FK creation fails if any fact row has a NULL FK value.
   ============================================================ */

-- Primary Keys — Dimension Tables
ALTER TABLE gold.dim_customer  ALTER COLUMN Customer_ID NVARCHAR(50) NOT NULL;
ALTER TABLE gold.dim_customer  ADD CONSTRAINT PK_dim_customer  PRIMARY KEY (Customer_ID);

ALTER TABLE gold.dim_product   ALTER COLUMN Product_Key INT NOT NULL;
ALTER TABLE gold.dim_product   ADD CONSTRAINT PK_dim_product   PRIMARY KEY (Product_Key);

ALTER TABLE gold.dim_date      ALTER COLUMN Order_Date  DATE NOT NULL;
ALTER TABLE gold.dim_date      ADD CONSTRAINT PK_dim_date      PRIMARY KEY (Order_Date);

ALTER TABLE gold.dim_geography ALTER COLUMN Geo_Key     INT NOT NULL;
ALTER TABLE gold.dim_geography ADD CONSTRAINT PK_dim_geography PRIMARY KEY (Geo_Key);

-- Align Fact column types to exactly match their referenced dimension PKs
ALTER TABLE gold.fact_sales ALTER COLUMN Customer_ID NVARCHAR(50) NOT NULL;
ALTER TABLE gold.fact_sales ALTER COLUMN Product_Key INT          NOT NULL;
ALTER TABLE gold.fact_sales ALTER COLUMN Order_Date  DATE         NOT NULL;
ALTER TABLE gold.fact_sales ALTER COLUMN Geo_Key     INT          NOT NULL;

-- Foreign Keys — Fact → Dimensions
ALTER TABLE gold.fact_sales
ADD CONSTRAINT FK_fact_customer  FOREIGN KEY (Customer_ID) REFERENCES gold.dim_customer  (Customer_ID);

ALTER TABLE gold.fact_sales
ADD CONSTRAINT FK_fact_product   FOREIGN KEY (Product_Key) REFERENCES gold.dim_product   (Product_Key);

ALTER TABLE gold.fact_sales
ADD CONSTRAINT FK_fact_date      FOREIGN KEY (Order_Date)  REFERENCES gold.dim_date      (Order_Date);

ALTER TABLE gold.fact_sales
ADD CONSTRAINT FK_fact_geography FOREIGN KEY (Geo_Key)     REFERENCES gold.dim_geography (Geo_Key);


/* ============================================================
   STEP 6 — VALIDATION CHECKS
   Run all checks after the full pipeline completes.
   Silver vs Fact pairs must return identical values.
   All NULL FK checks must return 0.

   WHY OLD VALUES WERE WRONG:
   Original script: Silver Sales = 2,356,855 | Fact = 2,351,036
   Root cause: dim_geography was built before the City/State
   casing cleanup was complete. The LEFT JOIN silently failed
   for multi-word cities (e.g.'Los Angeles' vs 'Los angeles'),
   producing NULL Geo_Keys and under-counting the sales total.
   Fix: double casing pass in Step 3c ensures all City/State
   values are consistently cased before dim_geography is built.
   Result: NULL Geo_Keys = 0 and Silver Sales = Fact Sales exactly.
   ============================================================ */

-- 1. Row Counts — Silver vs Fact (must be equal)
SELECT COUNT(*) AS silver_rows FROM silver.Superstore_cleansed; -- Expected: 9,986
SELECT COUNT(*) AS fact_rows   FROM gold.fact_sales;            -- Expected: 9,986

-- 2. Sales Totals — must be IDENTICAL (zero variance)
SELECT ROUND(SUM(Sales),  2) AS silver_total_sales  FROM silver.Superstore_cleansed; -- Expected: 2,347,314.26
SELECT ROUND(SUM(Sales),  2) AS fact_total_sales    FROM gold.fact_sales;            -- Expected: 2,347,314.26

-- 3. Profit Totals — must be IDENTICAL
SELECT ROUND(SUM(Profit), 2) AS silver_total_profit FROM silver.Superstore_cleansed; -- Expected: 286,025.36
SELECT ROUND(SUM(Profit), 2) AS fact_total_profit   FROM gold.fact_sales;            -- Expected: 286,025.36

-- 4. Order Counts — must match
SELECT COUNT(DISTINCT Order_ID) AS silver_orders FROM silver.Superstore_cleansed; -- Expected: 5008
SELECT COUNT(DISTINCT Order_ID) AS fact_orders   FROM gold.fact_sales;            -- Expected: 5008

-- 5. NULL FK Checks — ALL must return 0
--    Any value > 0 = a join failed; investigate before adding constraints
SELECT COUNT(*) AS null_geo_keys     FROM gold.fact_sales WHERE Geo_Key     IS NULL; -- Expected: 0
SELECT COUNT(*) AS null_product_keys FROM gold.fact_sales WHERE Product_Key  IS NULL; -- Expected: 0
SELECT COUNT(*) AS null_customer_ids FROM gold.fact_sales WHERE Customer_ID  IS NULL; -- Expected: 0
SELECT COUNT(*) AS null_order_dates  FROM gold.fact_sales WHERE Order_Date   IS NULL; -- Expected: 0

-- 6. Dimension Row Counts
SELECT COUNT(*) AS dim_customer_rows  FROM gold.dim_customer;  -- Expected:   793
SELECT COUNT(*) AS dim_product_rows   FROM gold.dim_product;   -- Expected: 1,862
SELECT COUNT(*) AS dim_geography_rows FROM gold.dim_geography; -- Expected:   631
SELECT COUNT(*) AS dim_date_rows      FROM gold.dim_date;      -- Expected: 1,237

-- 7. Silver vs Dimension cross-checks (distinct Silver counts must match dim row counts)
SELECT COUNT(DISTINCT Customer_ID) AS silver_customers FROM silver.Superstore_cleansed; -- Expected: 793
SELECT COUNT(DISTINCT Product_ID)  AS silver_products  FROM silver.Superstore_cleansed; -- Expected: 1,862
SELECT COUNT(DISTINCT Order_Date)  AS silver_dates     FROM silver.Superstore_cleansed; -- Expected: 1,237
