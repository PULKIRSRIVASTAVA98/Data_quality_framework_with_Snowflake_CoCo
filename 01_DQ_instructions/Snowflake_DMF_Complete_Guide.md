# Snowflake Data Metric Functions (DMFs) — Complete Guide

## What Are Data Metric Functions?

Data Metric Functions (DMFs) are **scheduled, reusable functions** in Snowflake that continuously measure data quality on tables and views. They run automatically on a schedule you define, and their results are stored in a system view you can query anytime.

**Key benefits:**
- Automated, continuous data quality monitoring
- No external tools required — native Snowflake feature
- Results queryable via SQL for dashboards and alerting
- Support both system (built-in) and custom (user-defined) functions

---

## Part 1: System DMFs (Built-in)

Snowflake provides 5 built-in DMFs under `SNOWFLAKE.CORE`:

| DMF | What It Measures | Attached To |
|-----|-----------------|-------------|
| `ROW_COUNT` | Total row count (volume monitoring) | Table `ON ()` |
| `NULL_COUNT` | Count of NULL values in a column | Column |
| `DUPLICATE_COUNT` | Count of duplicate values in a column | Column |
| `FRESHNESS` | Hours since last data update | Timestamp column |
| `UNIQUE_COUNT` | Count of distinct values | Column |

### Examples

```sql
-- ROW_COUNT (no column — monitors table volume)
ALTER TABLE my_db.my_schema.my_table
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

-- NULL_COUNT on a specific column
ALTER TABLE my_db.my_schema.my_table
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (EMAIL);

-- DUPLICATE_COUNT on a primary key column
ALTER TABLE my_db.my_schema.my_table
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (CUSTOMER_ID);

-- FRESHNESS on a timestamp column
ALTER TABLE my_db.my_schema.my_table
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (UPDATED_AT);

-- UNIQUE_COUNT on a column
ALTER TABLE my_db.my_schema.my_table
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.UNIQUE_COUNT ON (PRODUCT_ID);
```

---

## Part 2: Custom DMFs

Custom DMFs let you define any validation logic. They take a TABLE argument and return a NUMBER.

### Syntax

```sql
CREATE OR REPLACE DATA METRIC FUNCTION my_db.my_schema.MY_DMF_NAME(
  ARG_T TABLE(ARG_C1 <data_type>)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T WHERE <your_condition>
$$;
```

### Pattern 1: Email Validation

```sql
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_EMAIL_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND NOT ARG_C1 RLIKE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'
$$;
```

### Pattern 2: Phone Number Validation

```sql
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_PHONE_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND NOT ARG_C1 RLIKE '^[0-9]{10}$'
$$;
```

### Pattern 3: Range Check (Negative Values)

```sql
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.NEGATIVE_VALUE_COUNT(
  ARG_T TABLE(ARG_C1 NUMBER(18,2))
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T WHERE ARG_C1 < 0
$$;
```

### Pattern 4: Cross-Column Validation

```sql
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.APPROVED_EXCEEDS_REQUESTED_COUNT(
  ARG_T TABLE(ARG_C1 NUMBER(18,2), ARG_C2 NUMBER(18,2))
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T WHERE ARG_C2 IS NOT NULL AND ARG_C2 > ARG_C1
$$;

-- Attach with two columns
ALTER TABLE my_table
  ADD DATA METRIC FUNCTION APPROVED_EXCEEDS_REQUESTED_COUNT
  ON (REQUESTED_AMOUNT, APPROVED_AMOUNT);
```

### Pattern 5: Accepted Values Check

```sql
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.INVALID_ACCOUNT_TYPE_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND ARG_C1 NOT IN ('SAVINGS','CURRENT','LOAN')
$$;
```

### Pattern 6: Date Reasonableness

```sql
CREATE OR REPLACE DATA METRIC FUNCTION BANKING_DQ_DB.DQ_MONITORING.UNREASONABLE_DOB_COUNT(
  ARG_T TABLE(ARG_C1 DATE)
)
RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T
  WHERE ARG_C1 IS NOT NULL
    AND (YEAR(ARG_C1) > 2025 OR YEAR(ARG_C1) < 1900)
$$;
```

> **Note:** DMF bodies cannot use non-deterministic functions like `CURRENT_DATE`. Use hardcoded year boundaries instead.

---

## Part 3: Scheduling

Set when DMFs should run using `DATA_METRIC_SCHEDULE`:

```sql
-- Option 1: Run whenever data changes (recommended for most cases)
ALTER TABLE my_table SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

-- Option 2: Cron schedule (e.g., daily at 6am UTC)
ALTER TABLE my_table SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC';

-- Option 3: Minute interval (e.g., every 60 minutes)
ALTER TABLE my_table SET DATA_METRIC_SCHEDULE = '60 MINUTE';
```

---

## Part 4: Querying Results

DMF results are stored in a system view:

```sql
-- Latest results for a specific table
SELECT *
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME => 'MY_DB.MY_SCHEMA.MY_TABLE',
  REF_ENTITY_DOMAIN => 'TABLE'
))
ORDER BY MEASUREMENT_TIME DESC;

-- Trend analysis: last 7 days
SELECT
  DATE_TRUNC('DAY', MEASUREMENT_TIME) AS DAY,
  METRIC_NAME,
  AVG(VALUE) AS AVG_VALUE,
  MIN(VALUE) AS MIN_VALUE,
  MAX(VALUE) AS MAX_VALUE
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME => 'MY_DB.MY_SCHEMA.MY_TABLE',
  REF_ENTITY_DOMAIN => 'TABLE'
))
WHERE MEASUREMENT_TIME >= DATEADD('DAY', -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 1, 2;
```

---

## Part 5: Expectations (Thresholds)

Set pass/fail thresholds on DMFs:

```sql
-- NULL_COUNT on EMAIL should be 0 (no NULLs allowed)
ALTER TABLE my_table
  ALTER DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (EMAIL)
  SET EXPECTATION = 'EXPECT VALUE = 0';

-- Allow up to 5% duplicates
ALTER TABLE my_table
  ALTER DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (ORDER_ID)
  SET EXPECTATION = 'EXPECT PERCENTAGE_OF_TOTAL <= 5';
```

---

## Part 6: Schema-Level Bulk Attachment

Check all DMF attachments across a schema:

```sql
SELECT
  REF_ENTITY_NAME AS TABLE_NAME,
  METRIC_NAME,
  SCHEDULE_STATUS
FROM TABLE(MY_DB.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  REF_ENTITY_NAME => 'MY_DB.MY_SCHEMA',
  REF_ENTITY_DOMAIN => 'SCHEMA'
))
ORDER BY REF_ENTITY_NAME, METRIC_NAME;
```

---

## Part 7: Removing and Managing DMFs

```sql
-- Remove a DMF from a table
ALTER TABLE my_table
  DROP DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (EMAIL);

-- Suspend a DMF (stop running but keep attached)
ALTER TABLE my_table
  ALTER DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
  SUSPEND;

-- Resume a suspended DMF
ALTER TABLE my_table
  ALTER DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
  RESUME;

-- Drop a custom DMF definition
DROP DATA METRIC FUNCTION my_db.my_schema.MY_CUSTOM_DMF(TABLE(VARCHAR));
```

---

## Part 8: Production Use Cases

### Use Case 1: E-Commerce — Order Data Quality

```sql
-- Monitor: NULL order amounts, duplicate order IDs, volume drops
ALTER TABLE ECOM_DB.RAW.ORDERS SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';
ALTER TABLE ECOM_DB.RAW.ORDERS ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();
ALTER TABLE ECOM_DB.RAW.ORDERS ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (ORDER_AMOUNT);
ALTER TABLE ECOM_DB.RAW.ORDERS ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (ORDER_ID);
```

### Use Case 2: Healthcare — PII Validation

```sql
-- Custom DMF: SSN must be 9 digits
CREATE OR REPLACE DATA METRIC FUNCTION HC_DB.DQ.INVALID_SSN_COUNT(
  ARG_T TABLE(ARG_C1 VARCHAR)
) RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T WHERE ARG_C1 IS NOT NULL AND NOT ARG_C1 RLIKE '^[0-9]{9}$'
$$;
```

### Use Case 3: Financial Services — Transaction Monitoring

```sql
-- Negative amounts, invalid status codes, duplicate transaction IDs
CREATE OR REPLACE DATA METRIC FUNCTION FIN_DB.DQ.NEGATIVE_AMOUNT_COUNT(
  ARG_T TABLE(ARG_C1 NUMBER(18,2))
) RETURNS NUMBER AS
$$
  SELECT COUNT(*) FROM ARG_T WHERE ARG_C1 < 0
$$;
```

### Use Case 4: Data Mesh — Cross-Domain Quality Contracts

Each domain publishes quality SLAs via DMFs with expectations:

```sql
-- Domain: Customer — guarantee <1% null emails
ALTER TABLE CUSTOMER_DOMAIN.GOLD.CUSTOMERS
  ALTER DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (EMAIL)
  SET EXPECTATION = 'EXPECT PERCENTAGE_OF_TOTAL <= 1';
```

### Use Case 5: Circuit Breaker Pattern

Use DMF results to gate downstream pipelines:

```sql
-- In a task or procedure: check latest DMF results before proceeding
SELECT COUNT(*) AS FAILURES
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME => 'MY_DB.RAW.ORDERS',
  REF_ENTITY_DOMAIN => 'TABLE'
))
WHERE EXPECTATION_RESULT = 'FAILED'
  AND MEASUREMENT_TIME >= DATEADD('HOUR', -1, CURRENT_TIMESTAMP());
-- If FAILURES > 0, halt the pipeline
```

---

## Part 9: Cost Tracking

Monitor DMF execution costs:

```sql
SELECT
  START_TIME::DATE AS DAY,
  DATABASE_NAME,
  SCHEMA_NAME,
  DATA_METRIC_FUNCTION_NAME,
  SUM(CREDITS_USED) AS TOTAL_CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_METRIC_FUNCTION_USAGE_HISTORY
GROUP BY 1, 2, 3, 4
ORDER BY TOTAL_CREDITS DESC;
```

---

## Part 10: Best Practices

1. **Start with system DMFs** — they're free to use and cover common patterns (nulls, duplicates, volume)
2. **Use `TRIGGER_ON_CHANGES`** for most tables — runs only when data changes, minimizing cost
3. **Set expectations** on critical columns — enables automatic pass/fail tracking
4. **Keep custom DMFs deterministic** — avoid `CURRENT_DATE`, `RANDOM()`, etc. in DMF bodies
5. **Monitor costs** — use `DATA_METRIC_FUNCTION_USAGE_HISTORY` to track credit consumption
6. **Bulk attach at schema level** — use loops or scripts to attach DMFs across all tables in a schema
7. **Combine with alerting** — query DMF results in Snowflake alerts to get notified on failures

---

## Cheat Sheet — DMF Lifecycle

```sql
-- 1. Create custom DMF
CREATE OR REPLACE DATA METRIC FUNCTION db.schema.MY_DMF(ARG_T TABLE(ARG_C1 VARCHAR))
  RETURNS NUMBER AS $$ SELECT COUNT(*) FROM ARG_T WHERE <condition> $$;

-- 2. Set schedule on table
ALTER TABLE db.schema.my_table SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

-- 3. Attach DMF to table/column
ALTER TABLE db.schema.my_table ADD DATA METRIC FUNCTION db.schema.MY_DMF ON (COLUMN_NAME);

-- 4. Set expectation (optional)
ALTER TABLE db.schema.my_table ALTER DATA METRIC FUNCTION db.schema.MY_DMF ON (COLUMN_NAME)
  SET EXPECTATION = 'EXPECT VALUE = 0';

-- 5. Query results
SELECT * FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME => 'DB.SCHEMA.MY_TABLE', REF_ENTITY_DOMAIN => 'TABLE'));

-- 6. Suspend / Resume / Remove
ALTER TABLE db.schema.my_table ALTER DATA METRIC FUNCTION db.schema.MY_DMF ON (COLUMN_NAME) SUSPEND;
ALTER TABLE db.schema.my_table ALTER DATA METRIC FUNCTION db.schema.MY_DMF ON (COLUMN_NAME) RESUME;
ALTER TABLE db.schema.my_table DROP DATA METRIC FUNCTION db.schema.MY_DMF ON (COLUMN_NAME);
```
