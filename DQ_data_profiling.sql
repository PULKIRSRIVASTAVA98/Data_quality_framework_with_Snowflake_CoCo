/*=============================================================================
  DQ_data_profiling.sql
  Data Quality Framework - Step 1: Data Profiling & Assessment
  Source: BANKING_DQ_DB.RAW schema
=============================================================================*/

-- =============================================
-- 1. Table Inventory & Row Counts
-- =============================================
SELECT 'ACCOUNTS' AS TABLE_NAME, COUNT(*) AS ROW_CNT FROM BANKING_DQ_DB.RAW.ACCOUNTS
UNION ALL SELECT 'BRANCHES', COUNT(*) FROM BANKING_DQ_DB.RAW.BRANCHES
UNION ALL SELECT 'CUSTOMERS', COUNT(*) FROM BANKING_DQ_DB.RAW.CUSTOMERS
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM BANKING_DQ_DB.RAW.TRANSACTIONS
UNION ALL SELECT 'LOAN_APPLICATIONS', COUNT(*) FROM BANKING_DQ_DB.RAW.LOAN_APPLICATIONS;

-- Results:
--   ACCOUNTS:          10 rows
--   BRANCHES:           7 rows
--   CUSTOMERS:         10 rows
--   TRANSACTIONS:      12 rows
--   LOAN_APPLICATIONS: 10 rows

-- =============================================
-- 2. Column Metadata (all tables)
-- =============================================
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE,
       CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE
FROM BANKING_DQ_DB.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'RAW'
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- Results: 45 columns across 5 tables
--   ACCOUNTS (9 cols):          ACCOUNT_ID, CUSTOMER_ID, BRANCH_ID, ACCOUNT_TYPE, ACCOUNT_STATUS, OPEN_DATE, BALANCE, CURRENCY, CREATED_AT
--   BRANCHES (7 cols):          BRANCH_ID, BRANCH_NAME, CITY, STATE, IFSC_CODE, IS_ACTIVE, CREATED_AT
--   CUSTOMERS (10 cols):        CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, DATE_OF_BIRTH, KYC_STATUS, RISK_CATEGORY, BRANCH_ID, CREATED_AT
--   LOAN_APPLICATIONS (10 cols):APPLICATION_ID, CUSTOMER_ID, BRANCH_ID, LOAN_TYPE, APPLICATION_DATE, REQUESTED_AMOUNT, APPROVED_AMOUNT, APPLICATION_STATUS, CREDIT_SCORE, CREATED_AT
--   TRANSACTIONS (9 cols):      TRANSACTION_ID, ACCOUNT_ID, TRANSACTION_DATE, TRANSACTION_TYPE, AMOUNT, CHANNEL, MERCHANT_CATEGORY, TRANSACTION_STATUS, CREATED_AT

-- =============================================
-- 3. CUSTOMERS Table Profiling
-- =============================================
SELECT
  COUNT(*)                          AS TOTAL_ROWS,
  COUNT(CUSTOMER_ID)                AS CUSTOMER_ID_NON_NULL,
  COUNT(DISTINCT CUSTOMER_ID)       AS CUSTOMER_ID_DISTINCT,
  COUNT(FIRST_NAME)                 AS FIRST_NAME_NON_NULL,
  COUNT(DISTINCT FIRST_NAME)        AS FIRST_NAME_DISTINCT,
  COUNT(LAST_NAME)                  AS LAST_NAME_NON_NULL,
  COUNT(DISTINCT LAST_NAME)         AS LAST_NAME_DISTINCT,
  COUNT(EMAIL)                      AS EMAIL_NON_NULL,
  COUNT(DISTINCT EMAIL)             AS EMAIL_DISTINCT,
  COUNT(PHONE)                      AS PHONE_NON_NULL,
  COUNT(DISTINCT PHONE)             AS PHONE_DISTINCT,
  COUNT(DATE_OF_BIRTH)              AS DOB_NON_NULL,
  COUNT(KYC_STATUS)                 AS KYC_STATUS_NON_NULL,
  COUNT(DISTINCT KYC_STATUS)        AS KYC_STATUS_DISTINCT
FROM BANKING_DQ_DB.RAW.CUSTOMERS;

-- Results:
--   10 rows, all columns non-null
--   CUSTOMER_ID: 10 distinct (unique)
--   EMAIL: 10 distinct (unique)
--   PHONE: 10 distinct (unique)
--   KYC_STATUS: 3 distinct values (VERIFIED, PENDING, DONE)
--   Observation: KYC_STATUS contains 'DONE' which may be non-standard (expected: VERIFIED, PENDING, REJECTED)

-- KYC_STATUS distribution
SELECT KYC_STATUS, COUNT(*) AS CNT
FROM BANKING_DQ_DB.RAW.CUSTOMERS
GROUP BY KYC_STATUS;

-- Email format check
SELECT EMAIL, EMAIL RLIKE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' AS IS_VALID
FROM BANKING_DQ_DB.RAW.CUSTOMERS;

-- Phone format check (10-digit)
SELECT PHONE, PHONE RLIKE '^[0-9]{10}$' AS IS_VALID
FROM BANKING_DQ_DB.RAW.CUSTOMERS;

-- DOB reasonableness
SELECT DATE_OF_BIRTH, YEAR(DATE_OF_BIRTH) AS YEAR_VAL,
       CASE WHEN YEAR(DATE_OF_BIRTH) > 2025 OR YEAR(DATE_OF_BIRTH) < 1900 THEN 'UNREASONABLE' ELSE 'OK' END AS CHECK_RESULT
FROM BANKING_DQ_DB.RAW.CUSTOMERS;

-- =============================================
-- 4. ACCOUNTS Table Profiling
-- =============================================
SELECT
  COUNT(*)                          AS TOTAL_ROWS,
  COUNT(ACCOUNT_ID)                 AS ACCT_ID_NON_NULL,
  COUNT(DISTINCT ACCOUNT_ID)        AS ACCT_ID_DISTINCT,
  COUNT(CUSTOMER_ID)                AS CUST_ID_NON_NULL,
  COUNT(ACCOUNT_TYPE)               AS ACCT_TYPE_NON_NULL,
  COUNT(DISTINCT ACCOUNT_TYPE)      AS ACCT_TYPE_DISTINCT,
  COUNT(BALANCE)                    AS BALANCE_NON_NULL,
  MIN(BALANCE)                      AS BALANCE_MIN,
  MAX(BALANCE)                      AS BALANCE_MAX,
  COUNT(CURRENCY)                   AS CURRENCY_NON_NULL,
  COUNT(DISTINCT CURRENCY)          AS CURRENCY_DISTINCT,
  COUNT(ACCOUNT_STATUS)             AS STATUS_NON_NULL,
  COUNT(DISTINCT ACCOUNT_STATUS)    AS STATUS_DISTINCT
FROM BANKING_DQ_DB.RAW.ACCOUNTS;

-- Results:
--   10 rows, all columns non-null
--   ACCOUNT_ID: 10 distinct (unique)
--   ACCOUNT_TYPE: 3 distinct (SAVINGS, CURRENT, LOAN)
--   BALANCE: min=-1500.00, max=250000.00
--   CURRENCY: 2 distinct (INR, USD)
--   ACCOUNT_STATUS: 3 distinct (ACTIVE, DORMANT, CLOSED)
--   Observations:
--     - BALANCE has negative value (-1500.00) — potential data quality issue
--     - CURRENCY has 'USD' — expected all INR for Indian banking dataset

-- Balance distribution
SELECT BALANCE, CASE WHEN BALANCE < 0 THEN 'NEGATIVE' ELSE 'OK' END AS CHECK_RESULT
FROM BANKING_DQ_DB.RAW.ACCOUNTS;

-- Currency distribution
SELECT CURRENCY, COUNT(*) AS CNT
FROM BANKING_DQ_DB.RAW.ACCOUNTS
GROUP BY CURRENCY;

-- Account type distribution
SELECT ACCOUNT_TYPE, COUNT(*) AS CNT
FROM BANKING_DQ_DB.RAW.ACCOUNTS
GROUP BY ACCOUNT_TYPE;

-- Account status distribution
SELECT ACCOUNT_STATUS, COUNT(*) AS CNT
FROM BANKING_DQ_DB.RAW.ACCOUNTS
GROUP BY ACCOUNT_STATUS;

-- =============================================
-- 5. TRANSACTIONS Table Profiling
-- =============================================
SELECT
  COUNT(*)                              AS TOTAL_ROWS,
  COUNT(TRANSACTION_ID)                 AS TXN_ID_NON_NULL,
  COUNT(DISTINCT TRANSACTION_ID)        AS TXN_ID_DISTINCT,
  COUNT(ACCOUNT_ID)                     AS ACCT_ID_NON_NULL,
  COUNT(AMOUNT)                         AS AMOUNT_NON_NULL,
  MIN(AMOUNT)                           AS AMOUNT_MIN,
  MAX(AMOUNT)                           AS AMOUNT_MAX,
  COUNT(TRANSACTION_TYPE)               AS TXN_TYPE_NON_NULL,
  COUNT(DISTINCT TRANSACTION_TYPE)      AS TXN_TYPE_DISTINCT,
  COUNT(TRANSACTION_STATUS)             AS TXN_STATUS_NON_NULL,
  COUNT(DISTINCT TRANSACTION_STATUS)    AS TXN_STATUS_DISTINCT
FROM BANKING_DQ_DB.RAW.TRANSACTIONS;

-- Results:
--   12 rows, all columns non-null
--   TRANSACTION_ID: 12 distinct (unique)
--   AMOUNT: min=-50.00, max=9900.00
--   TRANSACTION_TYPE: 3 distinct (DEBIT, CREDIT, PAYMENT)
--   TRANSACTION_STATUS: 3 distinct (SUCCESS, DONE, FAILED)
--   Observations:
--     - AMOUNT has negative value (-50.00) — potential issue
--     - TRANSACTION_TYPE contains 'PAYMENT' — expected only DEBIT, CREDIT
--     - TRANSACTION_STATUS contains 'DONE' — expected SUCCESS, FAILED, PENDING

-- Transaction type distribution
SELECT TRANSACTION_TYPE, COUNT(*) AS CNT
FROM BANKING_DQ_DB.RAW.TRANSACTIONS
GROUP BY TRANSACTION_TYPE;

-- Transaction status distribution
SELECT TRANSACTION_STATUS, COUNT(*) AS CNT
FROM BANKING_DQ_DB.RAW.TRANSACTIONS
GROUP BY TRANSACTION_STATUS;

-- Negative amounts
SELECT TRANSACTION_ID, AMOUNT
FROM BANKING_DQ_DB.RAW.TRANSACTIONS
WHERE AMOUNT < 0;

-- =============================================
-- 6. LOAN_APPLICATIONS Table Profiling
-- =============================================
SELECT
  COUNT(*)                              AS TOTAL_ROWS,
  COUNT(APPLICATION_ID)                 AS APP_ID_NON_NULL,
  COUNT(DISTINCT APPLICATION_ID)        AS APP_ID_DISTINCT,
  COUNT(REQUESTED_AMOUNT)               AS REQ_AMT_NON_NULL,
  MIN(REQUESTED_AMOUNT)                 AS REQ_AMT_MIN,
  MAX(REQUESTED_AMOUNT)                 AS REQ_AMT_MAX,
  COUNT(APPROVED_AMOUNT)                AS APR_AMT_NON_NULL,
  MIN(APPROVED_AMOUNT)                  AS APR_AMT_MIN,
  MAX(APPROVED_AMOUNT)                  AS APR_AMT_MAX,
  COUNT(CREDIT_SCORE)                   AS CREDIT_NON_NULL,
  MIN(CREDIT_SCORE)                     AS CREDIT_MIN,
  MAX(CREDIT_SCORE)                     AS CREDIT_MAX,
  COUNT(LOAN_TYPE)                      AS LOAN_TYPE_NON_NULL,
  COUNT(DISTINCT LOAN_TYPE)             AS LOAN_TYPE_DISTINCT,
  COUNT(APPLICATION_STATUS)             AS APP_STATUS_NON_NULL,
  COUNT(DISTINCT APPLICATION_STATUS)    AS APP_STATUS_DISTINCT
FROM BANKING_DQ_DB.RAW.LOAN_APPLICATIONS;

-- Results:
--   10 rows
--   APPLICATION_ID: 10 distinct (unique)
--   REQUESTED_AMOUNT: min=0.00, max=5000000.00
--   APPROVED_AMOUNT: only 4 non-null (6 NULLs = pending/rejected apps)
--   CREDIT_SCORE: min=610, max=900
--   LOAN_TYPE: 5 distinct (HOME, CAR, PERSONAL, EDUCATION, BUSINESS)
--   APPLICATION_STATUS: 3 distinct (APPROVED, PENDING, REJECTED)
--   Observations:
--     - REQUESTED_AMOUNT has 0.00 value — zero loan request is suspicious
--     - CREDIT_SCORE max=900 exceeds standard max of 850
--     - APPROVED_AMOUNT > REQUESTED_AMOUNT check needed for approved loans

-- Cross-column: Approved > Requested
SELECT APPLICATION_ID, REQUESTED_AMOUNT, APPROVED_AMOUNT
FROM BANKING_DQ_DB.RAW.LOAN_APPLICATIONS
WHERE APPROVED_AMOUNT IS NOT NULL AND APPROVED_AMOUNT > REQUESTED_AMOUNT;

-- Credit score out of range
SELECT APPLICATION_ID, CREDIT_SCORE
FROM BANKING_DQ_DB.RAW.LOAN_APPLICATIONS
WHERE CREDIT_SCORE < 300 OR CREDIT_SCORE > 850;

-- Loan type distribution
SELECT LOAN_TYPE, COUNT(*) AS CNT
FROM BANKING_DQ_DB.RAW.LOAN_APPLICATIONS
GROUP BY LOAN_TYPE;

-- =============================================
-- 7. BRANCHES Table Profiling
-- =============================================
SELECT
  COUNT(*)                          AS TOTAL_ROWS,
  COUNT(BRANCH_ID)                  AS BRANCH_ID_NON_NULL,
  COUNT(DISTINCT BRANCH_ID)         AS BRANCH_ID_DISTINCT,
  COUNT(BRANCH_NAME)                AS BRANCH_NAME_NON_NULL,
  COUNT(DISTINCT BRANCH_NAME)       AS BRANCH_NAME_DISTINCT,
  COUNT(IFSC_CODE)                  AS IFSC_NON_NULL,
  COUNT(DISTINCT IFSC_CODE)         AS IFSC_DISTINCT
FROM BANKING_DQ_DB.RAW.BRANCHES;

-- Results:
--   7 rows
--   BRANCH_ID: 7 distinct (unique)
--   BRANCH_NAME: 6 non-null (1 NULL) — missing branch name
--   IFSC_CODE: 7 non-null, 7 distinct
--   Observation: 1 BRANCH_NAME is NULL

-- IFSC format check (^[A-Z]{4}[0-9]{7}$)
SELECT BRANCH_ID, IFSC_CODE, IFSC_CODE RLIKE '^[A-Z]{4}[0-9]{7}$' AS IS_VALID
FROM BANKING_DQ_DB.RAW.BRANCHES;

-- NULL branch names
SELECT * FROM BANKING_DQ_DB.RAW.BRANCHES WHERE BRANCH_NAME IS NULL;

-- =============================================
-- 8. Categorical Value Distribution Summary
-- =============================================
SELECT 'ACCOUNTS.ACCOUNT_TYPE' AS COLUMN_PATH, LISTAGG(DISTINCT ACCOUNT_TYPE, ', ') AS DISTINCT_VALUES FROM BANKING_DQ_DB.RAW.ACCOUNTS
UNION ALL SELECT 'ACCOUNTS.ACCOUNT_STATUS', LISTAGG(DISTINCT ACCOUNT_STATUS, ', ') FROM BANKING_DQ_DB.RAW.ACCOUNTS
UNION ALL SELECT 'ACCOUNTS.CURRENCY', LISTAGG(DISTINCT CURRENCY, ', ') FROM BANKING_DQ_DB.RAW.ACCOUNTS
UNION ALL SELECT 'CUSTOMERS.KYC_STATUS', LISTAGG(DISTINCT KYC_STATUS, ', ') FROM BANKING_DQ_DB.RAW.CUSTOMERS
UNION ALL SELECT 'LOAN_APPLICATIONS.LOAN_TYPE', LISTAGG(DISTINCT LOAN_TYPE, ', ') FROM BANKING_DQ_DB.RAW.LOAN_APPLICATIONS
UNION ALL SELECT 'LOAN_APPLICATIONS.APPLICATION_STATUS', LISTAGG(DISTINCT APPLICATION_STATUS, ', ') FROM BANKING_DQ_DB.RAW.LOAN_APPLICATIONS
UNION ALL SELECT 'TRANSACTIONS.TRANSACTION_TYPE', LISTAGG(DISTINCT TRANSACTION_TYPE, ', ') FROM BANKING_DQ_DB.RAW.TRANSACTIONS
UNION ALL SELECT 'TRANSACTIONS.TRANSACTION_STATUS', LISTAGG(DISTINCT TRANSACTION_STATUS, ', ') FROM BANKING_DQ_DB.RAW.TRANSACTIONS;

-- Results:
--   ACCOUNTS.ACCOUNT_TYPE:               CURRENT, SAVINGS, LOAN
--   ACCOUNTS.ACCOUNT_STATUS:             ACTIVE, DORMANT, CLOSED
--   ACCOUNTS.CURRENCY:                   USD, INR
--   CUSTOMERS.KYC_STATUS:                VERIFIED, PENDING, DONE        ← 'DONE' is non-standard
--   LOAN_APPLICATIONS.LOAN_TYPE:         CAR, HOME, EDUCATION, PERSONAL, BUSINESS
--   LOAN_APPLICATIONS.APPLICATION_STATUS:PENDING, APPROVED, REJECTED
--   TRANSACTIONS.TRANSACTION_TYPE:       DEBIT, CREDIT, PAYMENT         ← 'PAYMENT' is non-standard
--   TRANSACTIONS.TRANSACTION_STATUS:     SUCCESS, DONE, FAILED          ← 'DONE' is non-standard

-- =============================================
-- 9. Profiling Summary — Issues Found
-- =============================================
/*
| # | Table            | Issue                                     | Severity |
|---|------------------|-------------------------------------------|----------|
| 1 | ACCOUNTS         | Negative BALANCE (-1500.00)               | HIGH     |
| 2 | ACCOUNTS         | Non-INR CURRENCY (USD found)              | MEDIUM   |
| 3 | BRANCHES         | NULL BRANCH_NAME (1 record)               | HIGH     |
| 4 | CUSTOMERS        | KYC_STATUS 'DONE' not in accepted values  | HIGH     |
| 5 | TRANSACTIONS     | Negative AMOUNT (-50.00)                  | HIGH     |
| 6 | TRANSACTIONS     | TRANSACTION_TYPE 'PAYMENT' non-standard   | HIGH     |
| 7 | TRANSACTIONS     | TRANSACTION_STATUS 'DONE' non-standard    | HIGH     |
| 8 | LOAN_APPLICATIONS| REQUESTED_AMOUNT = 0.00                   | HIGH     |
| 9 | LOAN_APPLICATIONS| CREDIT_SCORE > 850 (max=900)              | HIGH     |
|10 | LOAN_APPLICATIONS| APPROVED_AMOUNT > REQUESTED_AMOUNT        | HIGH     |
*/
