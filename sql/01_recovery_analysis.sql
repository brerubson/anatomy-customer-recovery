-- CLEANING STEP 1: Check for missing values across key customer fields
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(customer_id)          AS missing_customer_id,
    COUNT(*) - COUNT(region)               AS missing_region,
    COUNT(*) - COUNT(customer_since)       AS missing_customer_since,
    COUNT(*) - COUNT(household_type)       AS missing_household_type
FROM raw_customers;

-- CLEANING STEP 2: Check for duplicate customer_id values in raw_customers
SELECT
    customer_id,
    COUNT(*) AS num_rows
FROM raw_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- CLEANING STEP 3: Check for duplicate customer records under different customer_id values
-- (same person, re-entered with a new ID — not caught by checking IDs alone)
SELECT
    age_group, gender, household_type, region, acquisition_channel, customer_since,
    COUNT(*) AS num_matching_rows,
    STRING_AGG(customer_id, ', ') AS customer_ids
FROM raw_customers
GROUP BY age_group, gender, household_type, region, acquisition_channel, customer_since
HAVING COUNT(*) > 1;

-- CLEANING STEP 4: Remove confirmed duplicate customers (ID ends in "_DUP")
-- Only these 8 have direct evidence of being the same customer re-entered
-- (an ID that is literally the original + "_DUP"). The other 3 candidate pairs
-- from Step 3 were reviewed and judged coincidental matches, not duplicates,
-- and are kept.
DELETE FROM raw_customers
WHERE customer_id LIKE '%\_DUP' ESCAPE '\';


-- CLEANING STEP 5: Check for fully duplicated transaction line rows
-- (every column identical - same order, product, price, everything)
SELECT
    order_id, product_id, quantity, unit_price_gbp, discount_gbp,
    net_sales_gbp, unit_cost_gbp, cogs_gbp, gross_profit_gbp,
    channel, region, return_flag, order_date,
    COUNT(*) AS num_matching_rows
FROM raw_transactions
GROUP BY order_id, product_id, quantity, unit_price_gbp, discount_gbp,
    net_sales_gbp, unit_cost_gbp, cogs_gbp, gross_profit_gbp,
    channel, region, return_flag, order_date
HAVING COUNT(*) > 1;


-- CLEANING STEP 6: Remove duplicate transaction rows, keeping one copy of each
-- Transactions have no unique row ID, so we number each row within its
-- duplicate group and delete every copy except the first (row_num = 1)
DELETE FROM raw_transactions
WHERE ctid IN (
    SELECT ctid FROM (
        SELECT
            ctid,
            ROW_NUMBER() OVER (
                PARTITION BY order_id, product_id, quantity, unit_price_gbp, discount_gbp,
                    net_sales_gbp, unit_cost_gbp, cogs_gbp, gross_profit_gbp,
                    channel, region, return_flag, order_date
                ORDER BY ctid
            ) AS row_num
        FROM raw_transactions
    ) ranked
    WHERE row_num > 1
);


-- CLEANING STEP 7: Check for impossible Quantity values
SELECT quantity, COUNT(*) AS num_rows
FROM raw_transactions
WHERE quantity <= 0
GROUP BY quantity;

-- CLEANING STEP 8: Remove transaction rows with impossible Quantity values
-- (0 = contributes nothing, likely junk; -1 = no clear business meaning here
-- since returns are already tracked separately via return_flag)
DELETE FROM raw_transactions
WHERE quantity <= 0;

-- CLEANING STEP 9: Check for implausible Unit_Price values
-- Join to products so we can compare the price actually charged
-- against the product's original list price
SELECT
    t.product_id,
    p.product_name,
    p.selling_price_gbp   AS list_price,
    t.unit_price_gbp      AS charged_price,
    t.order_date
FROM raw_transactions t
JOIN raw_products p ON t.product_id = p.product_id
WHERE t.unit_price_gbp > p.selling_price_gbp * 3
ORDER BY t.unit_price_gbp DESC;

-- CLEANING STEP 10: Fix Unit_Price values inflated 100x (decimal entry error)
-- Same threshold as Step 9 - anything charged at more than 3x list price
-- Correcting rather than deleting: only the price field is broken, everything
-- else on the row (customer, product, quantity, date) is legitimate data
UPDATE raw_transactions t
SET unit_price_gbp = ROUND(t.unit_price_gbp / 100, 2)
FROM raw_products p
WHERE t.product_id = p.product_id
  AND t.unit_price_gbp > p.selling_price_gbp * 3;
-- CLEANING STEP 11: Recalculate Net_Sales, COGS and Gross_Profit for ALL rows
-- from their base fields, rather than trusting the stored calculated values.
-- This corrects both the 12 rows fixed in Step 10 (their derived fields were
-- never re-derived from the corrected price) and any other rows where the
-- calculated fields had drifted from their inputs, in one pass.
UPDATE raw_transactions
SET
    net_sales_gbp    = ROUND((unit_price_gbp * quantity) - discount_gbp, 2),
    cogs_gbp         = ROUND(unit_cost_gbp * quantity, 2),
    gross_profit_gbp = ROUND(((unit_price_gbp * quantity) - discount_gbp) - (unit_cost_gbp * quantity), 2);

-- CLEANING STEP 12: Check for missing Customer_ID, and for Product_ID/Customer_ID
-- values that don't exist in their parent table (referential integrity)
SELECT 'Missing customer_id' AS issue, COUNT(*) AS num_rows
FROM raw_transactions
WHERE customer_id IS NULL

UNION ALL

SELECT 'customer_id not found in raw_customers', COUNT(*)
FROM raw_transactions t
LEFT JOIN raw_customers c ON t.customer_id = c.customer_id
WHERE t.customer_id IS NOT NULL AND c.customer_id IS NULL

UNION ALL

SELECT 'product_id not found in raw_products', COUNT(*)
FROM raw_transactions t
LEFT JOIN raw_products p ON t.product_id = p.product_id
WHERE p.product_id IS NULL;


-- CLEANING STEP 13: Remove transaction rows that fail referential integrity
-- (no customer_id, or a product_id that doesn't exist in raw_products) -
-- neither can be attributed to a real customer or a real product, so cannot
-- be repaired, only removed
DELETE FROM raw_transactions
WHERE customer_id IS NULL
   OR product_id NOT IN (SELECT product_id FROM raw_products);  

-- CLEANING STEP 14: List every distinct Region value in raw_transactions
-- to spot spelling/casing inconsistencies by eye
SELECT region, COUNT(*) AS num_rows
FROM raw_transactions
GROUP BY region
ORDER BY region;

-- CLEANING STEP 15: Standardise inconsistent Region spellings in raw_transactions
UPDATE raw_transactions SET region = 'East of England' WHERE region ILIKE '%east%england%';
UPDATE raw_transactions SET region = 'North West' WHERE region ILIKE '%north%west%' OR region ILIKE 'n.west';
UPDATE raw_transactions SET region = 'Yorkshire & Humber' WHERE region ILIKE '%yorkshire%';

-- CLEANING STEP 16: Check for blank/whitespace Product_Name values
SELECT product_id, ecosystem, category, subcategory, product_name
FROM raw_products
WHERE TRIM(product_name) = '';

-- CLEANING STEP 17: Replace blank Product_Name with a label built from known
-- fields (ecosystem/subcategory) - NOT a fabricated specific name, since we
-- have no way of knowing what the original name actually was
UPDATE raw_products
SET product_name = 'Unknown Product - ' || subcategory
WHERE TRIM(product_name) = '';


-- CLEANING STEP 18: Replace missing Region with an explicit 'Unknown' label
-- rather than leaving it NULL - a real value that shows up honestly in
-- region-based reports instead of silently disappearing from GROUP BY results
UPDATE raw_customers
SET region = 'Unknown'
WHERE region IS NULL;   

-- CLEANING STEP 19: Final validation - re-run the original checks, expect
-- zero issues across the board
SELECT 'duplicate customer_id' AS check_name, COUNT(*) AS issues
FROM (SELECT customer_id FROM raw_customers GROUP BY customer_id HAVING COUNT(*) > 1) x
UNION ALL
SELECT 'null region (customers)', COUNT(*) FROM raw_customers WHERE region IS NULL
UNION ALL
SELECT 'null customer_id (transactions)', COUNT(*) FROM raw_transactions WHERE customer_id IS NULL
UNION ALL
SELECT 'invalid product_id', COUNT(*) FROM raw_transactions WHERE product_id NOT IN (SELECT product_id FROM raw_products)
UNION ALL
SELECT 'quantity <= 0', COUNT(*) FROM raw_transactions WHERE quantity <= 0
UNION ALL
SELECT 'price > 3x list price', COUNT(*) FROM raw_transactions t JOIN raw_products p ON t.product_id = p.product_id WHERE t.unit_price_gbp > p.selling_price_gbp * 3
UNION ALL
SELECT 'blank product_name', COUNT(*) FROM raw_products WHERE TRIM(product_name) = '';

-- CLEANING STEP 20: Rename tables now that cleaning is complete.
-- The original untouched raw CSVs remain available outside the database
-- as the true immutable raw source, per the process note in Step 12.
ALTER TABLE raw_customers RENAME TO clean_customers;
ALTER TABLE raw_products RENAME TO clean_products;
ALTER TABLE raw_transactions RENAME TO clean_transactions;