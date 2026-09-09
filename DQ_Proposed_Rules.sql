/*=============================================================================
  DQ_Proposed_Rules.sql
  Data Quality Framework - Step 2: Recommended Rules & Custom Functions
  Based on profiling results from DQ_data_profiling.sql
=============================================================================*/

/*
=============================================================================
RULE RECOMMENDATION MATRIX
=============================================================================
Based on profiling of BANKING_DQ_DB.RAW (5 tables, 45 columns, 49 total rows),
the following 42 data quality rules are recommended across 7 quality dimensions:

| Dimension    | Rule Count | Description                              |
|-------------|------------|------------------------------------------|
| Volume      | 5          | Row count monitoring per table           |
| Completeness| 11         | NULL checks on critical columns          |
| Uniqueness  | 6          | Duplicate detection on key columns       |
| Validity    | 5          | Format validation (email, phone, IFSC, credit score, loan type) |
| Accuracy    | 4          | Range checks (balance, amount, DOB, approved vs requested) |
| Consistency | 7          | Accepted value checks on categorical columns |

Total: 42 rules (22 System DMFs + 16 Custom DMFs + 4 Cross-column DMFs)
=============================================================================
*/

-- =============================================
-- PROPOSED SYSTEM DMF RULES (22 rules)
-- =============================================
/*
These use built-in SNOWFLAKE.CORE DMFs — no custom code needed.

| Rule ID | Table            | DMF              | Column           | Criticality |
|---------|------------------|------------------|------------------|-------------|
| LA01    | LOAN_APPLICATIONS| ROW_COUNT        | (table-level)    | HIGH        |
| LA02    | LOAN_APPLICATIONS| NULL_COUNT       | APPLICATION_ID   | HIGH        |
| LA03    | LOAN_APPLICATIONS| NULL_COUNT       | REQUESTED_AMOUNT | HIGH        |
| LA04    | LOAN_APPLICATIONS| NULL_COUNT       | CREDIT_SCORE     | HIGH        |
| LA05    | LOAN_APPLICATIONS| DUPLICATE_COUNT  | APPLICATION_ID   | HIGH        |
| CU01    | CUSTOMERS        | ROW_COUNT        | (table-level)    | HIGH        |
| CU02    | CUSTOMERS        | NULL_COUNT       | CUSTOMER_ID      | HIGH        |
| CU03    | CUSTOMERS        | NULL_COUNT       | EMAIL            | HIGH        |
| CU04    | CUSTOMERS        | NULL_COUNT       | PHONE            | HIGH        |
| CU05    | CUSTOMERS        | DUPLICATE_COUNT  | CUSTOMER_ID      | HIGH        |
| CU06    | CUSTOMERS        | DUPLICATE_COUNT  | EMAIL            | MEDIUM      |
| AC01    | ACCOUNTS         | ROW_COUNT        | (table-level)    | HIGH        |
| AC02    | ACCOUNTS         | NULL_COUNT       | ACCOUNT_ID       | HIGH        |
| AC03    | ACCOUNTS         | NULL_COUNT       | CUSTOMER_ID      | HIGH        |
| AC04    | ACCOUNTS         | NULL_COUNT       | BALANCE          | HIGH        |
| AC05    | ACCOUNTS         | DUPLICATE_COUNT  | ACCOUNT_ID       | HIGH        |
| TX01    | TRANSACTIONS     | ROW_COUNT        | (table-level)    | HIGH        |
| TX02    | TRANSACTIONS     | NULL_COUNT       | TRANSACTION_ID   | HIGH        |
| TX03    | TRANSACTIONS     | NULL_COUNT       | AMOUNT           | HIGH        |
| TX04    | TRANSACTIONS     | NULL_COUNT       | ACCOUNT_ID       | HIGH        |
| TX05    | TRANSACTIONS     | DUPLICATE_COUNT  | TRANSACTION_ID   | HIGH        |
| BR01    | BRANCHES         | ROW_COUNT        | (table-level)    | HIGH        |
| BR02    | BRANCHES         | NULL_COUNT       | BRANCH_ID        | HIGH        |
| BR03    | BRANCHES         | NULL_COUNT       | BRANCH_NAME      | HIGH        |
| BR04    | BRANCHES         | DUPLICATE_COUNT  | BRANCH_ID        | HIGH        |
*/

-- =============================================
-- PROPOSED CUSTOM DMF RULES (20 rules)
-- =============================================

/*
=== VALIDITY DIMENSION — Format Validation ===

1. INVALID_EMAIL_COUNT
   - Table: CUSTOMERS
   - Column: EMAIL
   - Rationale: Profiling shows 10 distinct emails; regex validation needed for format compliance
   - Pattern: ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_EMAIL_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND NOT ARG_C1 RLIKE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'
$$;

/*
2. INVALID_PHONE_COUNT
   - Table: CUSTOMERS
   - Column: PHONE
   - Rationale: Indian banking — phone numbers should be exactly 10 digits
   - Pattern: ^[0-9]{10}$
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_PHONE_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND NOT ARG_C1 RLIKE '^[0-9]{10}$'
$$;

/*
3. INVALID_IFSC_COUNT
   - Table: BRANCHES
   - Column: IFSC_CODE
   - Rationale: IFSC codes follow strict format: 4 uppercase letters + 7 digits
   - Pattern: ^[A-Z]{4}[0-9]{7}$
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_IFSC_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND NOT ARG_C1 RLIKE '^[A-Z]{4}[0-9]{7}$'
$$;

/*
4. CREDIT_SCORE_OUT_OF_RANGE_COUNT
   - Table: LOAN_APPLICATIONS
   - Column: CREDIT_SCORE
   - Rationale: Profiling found max=900 which exceeds standard range 300-850
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.CREDIT_SCORE_OUT_OF_RANGE_COUNT(
  ARG_T TABLE(ARG_C1 NUMBER(5,0))
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL AND (ARG_C1 < 300 OR ARG_C1 > 850)
$$;

/*
=== ACCURACY DIMENSION — Range & Reasonableness Checks ===

5. NEGATIVE_VALUE_COUNT
   - Tables: ACCOUNTS (BALANCE), TRANSACTIONS (AMOUNT)
   - Rationale: Profiling found BALANCE min=-1500.00 and AMOUNT min=-50.00
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.NEGATIVE_VALUE_COUNT(
  ARG_T TABLE(ARG_C1 NUMBER(18,2))
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T WHERE ARG_C1 < 0
$$;

/*
6. ZERO_OR_NEGATIVE_COUNT
   - Table: LOAN_APPLICATIONS
   - Column: REQUESTED_AMOUNT
   - Rationale: Profiling found min=0.00 — loan requests should be positive
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.ZERO_OR_NEGATIVE_COUNT(
  ARG_T TABLE(ARG_C1 NUMBER(18,2))
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T WHERE ARG_C1 <= 0
$$;

/*
7. UNREASONABLE_DOB_COUNT
   - Table: CUSTOMERS
   - Column: DATE_OF_BIRTH
   - Rationale: DOB should be between 1900 and 2025 (no future dates, no impossibly old dates)
   - Note: DMF bodies cannot use CURRENT_DATE; hardcoded year boundary instead
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.UNREASONABLE_DOB_COUNT(
  ARG_T TABLE(ARG_C1 DATE)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND (YEAR(ARG_C1) > 2025 OR YEAR(ARG_C1) < 1900)
$$;

/*
8. APPROVED_EXCEEDS_REQUESTED_COUNT (Cross-Column)
   - Table: LOAN_APPLICATIONS
   - Columns: REQUESTED_AMOUNT, APPROVED_AMOUNT
   - Rationale: Profiling identified cases where approved amount exceeds requested
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.APPROVED_EXCEEDS_REQUESTED_COUNT(
  ARG_T TABLE(ARG_C1 NUMBER(18,2), ARG_C2 NUMBER(18,2))
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T WHERE ARG_C2 IS NOT NULL AND ARG_C2 > ARG_C1
$$;

/*
=== CONSISTENCY DIMENSION — Accepted Value Checks ===

9. INVALID_ACCOUNT_TYPE_COUNT
   - Table: ACCOUNTS
   - Column: ACCOUNT_TYPE
   - Accepted: SAVINGS, CURRENT, LOAN
   - Rationale: Profiling confirmed 3 distinct values — enforce as rule
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_ACCOUNT_TYPE_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND ARG_C1 NOT IN ('SAVINGS','CURRENT','LOAN')
$$;

/*
10. INVALID_ACCOUNT_STATUS_COUNT
    - Table: ACCOUNTS
    - Column: ACCOUNT_STATUS
    - Accepted: ACTIVE, DORMANT, CLOSED
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_ACCOUNT_STATUS_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND ARG_C1 NOT IN ('ACTIVE','DORMANT','CLOSED')
$$;

/*
11. NON_INR_CURRENCY_COUNT
    - Table: ACCOUNTS
    - Column: CURRENCY
    - Rationale: Profiling found USD — Indian banking should be INR only
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.NON_INR_CURRENCY_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL AND ARG_C1 != 'INR'
$$;

/*
12. INVALID_KYC_STATUS_COUNT
    - Table: CUSTOMERS
    - Column: KYC_STATUS
    - Accepted: VERIFIED, PENDING, REJECTED
    - Rationale: Profiling found 'DONE' which is non-standard
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_KYC_STATUS_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND ARG_C1 NOT IN ('VERIFIED','PENDING','REJECTED')
$$;

/*
13. INVALID_TXN_TYPE_COUNT
    - Table: TRANSACTIONS
    - Column: TRANSACTION_TYPE
    - Accepted: DEBIT, CREDIT
    - Rationale: Profiling found 'PAYMENT' which is non-standard
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_TXN_TYPE_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND ARG_C1 NOT IN ('DEBIT','CREDIT')
$$;

/*
14. INVALID_TXN_STATUS_COUNT
    - Table: TRANSACTIONS
    - Column: TRANSACTION_STATUS
    - Accepted: SUCCESS, FAILED, PENDING
    - Rationale: Profiling found 'DONE' which is non-standard
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_TXN_STATUS_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND ARG_C1 NOT IN ('SUCCESS','FAILED','PENDING')
$$;

/*
15. INVALID_LOAN_TYPE_COUNT
    - Table: LOAN_APPLICATIONS
    - Column: LOAN_TYPE
    - Accepted: HOME, CAR, PERSONAL, EDUCATION, BUSINESS
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_LOAN_TYPE_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND ARG_C1 NOT IN ('HOME','CAR','PERSONAL','EDUCATION','BUSINESS')
$$;

/*
16. INVALID_APP_STATUS_COUNT
    - Table: LOAN_APPLICATIONS
    - Column: APPLICATION_STATUS
    - Accepted: APPROVED, PENDING, REJECTED
*/
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_APP_STATUS_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND ARG_C1 NOT IN ('APPROVED','PENDING','REJECTED')
$$;
