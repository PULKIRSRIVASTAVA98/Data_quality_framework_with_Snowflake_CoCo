# Skill: Snowflake Data Quality Framework using CoCo

## Project Goal

Build an enterprise grade end-to-end **Data Quality Framework in Snowflake** that can monitor all important tables across selected schemas, apply data quality rules, log rule execution results, detect anomalies, generate data quality scores and provide a Streamlit dashboard for detailed visualization.

This framework should use **Snowflake Data Metric Functions (DMFs)**, custom validation logic, anomaly detection and orchestration. Snowflake CoCo /data-quality Skill should help generate the SQL, recommend monitors, create reusable framework objects, and support root cause analysis.

---

## Step wise Approach

Read all the steps and perform them sequentially. Confirm before moving to next step.

Note: Create all scripts in workspace {Data_quality_framework_with_Snowflake_CoCo}

1. DQ_data_profiling.sql: To store all profiling and analysis sqls for source dataset from Step 1
2. DQ_Proposed_Rules.sql: To store all recommended rules and custom functions.
3. DQ_Rules.sql : Stores all the system/ custom DMFs created and attached to tables as part of Step 3
4. DQ_Framework_Config.sql : Steps all the framework table DDLs and config data inserts from Step 4
5. DQ_Orchestration.sql : SP to execute all rules and log results from Step 5
6. dq-monitoring-dashboard/ : Streamlit dashboard app from Step 7

---

## Step 1: Data Profiling & Assessment

- Profile the dataset under `BANKING_DQ_DB.RAW` schema
- Identify all tables, columns, data types, null counts, distinct counts
- Detect patterns, outliers, and potential quality issues
- Save profiling SQL to `DQ_data_profiling.sql`

## Step 2: Rule Recommendation

- Based on profiling results, recommend data quality rules
- Include system DMFs (ROW_COUNT, NULL_COUNT, DUPLICATE_COUNT, FRESHNESS, UNIQUE_COUNT)
- Recommend custom DMFs for business-specific validations
- Save recommendations to `DQ_Proposed_Rules.sql`

## Step 3: DMF Creation & Attachment

- Create all custom DMFs in `BANKING_DQ_DB.DQ_MONITORING` schema
- Set `DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES'` on all tables
- Attach system and custom DMFs to appropriate tables/columns
- Save all DDL to `DQ_Rules.sql`

## Step 4: Framework Tables & Configuration

- Create framework tables: DQ_RUN_CONTROL, DQ_RULE_CONFIG, DQ_RULE_RESULTS, DQ_ERROR_RECORDS, DQ_ANOMALY_RESULTS
- Load all 42 rules into DQ_RULE_CONFIG with metadata (rule_id, name, type, criticality, table, column, SQL, threshold, dimension)
- Save DDL and INSERTs to `DQ_Framework_Config.sql`

## Step 5: Orchestration

- Create stored procedure `SP_RUN_DQ_FRAMEWORK(P_TRIGGERED_BY VARCHAR)`
- Iterate over all active rules in DQ_RULE_CONFIG
- Execute each rule dynamically, capture results
- Log to DQ_RUN_CONTROL and DQ_RULE_RESULTS
- Handle errors gracefully with exception blocks
- Save to `DQ_Orchestration.sql`

## Step 6: Execution & Validation

- Execute: `CALL SP_RUN_DQ_FRAMEWORK('MANUAL_TEST')`
- Verify all 42 rules processed with 0 errors
- Review pass/fail summary

## Step 7: Streamlit Dashboard

- Create a monitoring dashboard in `dq-monitoring-dashboard/`
- Display: overall DQ score, pass/fail by table, rule details, trend over time
- Use `st.connection("snowflake")` for data access
