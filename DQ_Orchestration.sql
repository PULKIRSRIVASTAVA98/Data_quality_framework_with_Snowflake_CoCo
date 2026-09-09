/*=============================================================================
  DQ_Orchestration.sql
  Data Quality Framework - Step 5: Orchestration Stored Procedure
  Uses RESULTSET and $$ approach for dynamic rule execution and logging
=============================================================================*/

CREATE OR REPLACE PROCEDURE BANKING_DQ_DB.DQ_MONITORING.SP_RUN_DQ_FRAMEWORK(P_TRIGGERED_BY VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    V_RUN_ID VARCHAR;
    V_RULE_ID VARCHAR;
    V_RULE_NAME VARCHAR;
    V_RULE_TYPE VARCHAR;
    V_CRITICALITY VARCHAR;
    V_DB_NAME VARCHAR;
    V_TABLE_NM VARCHAR;
    V_COLUMN_NM VARCHAR;
    V_RULE_SQL VARCHAR;
    V_THRESHOLD NUMBER(18,4);
    V_RULE_DESCRIPTION VARCHAR;
    V_ACTUAL_VALUE NUMBER;
    V_TOTAL_ROWS NUMBER;
    V_FAILED_COUNT NUMBER;
    V_PASS_PCT NUMBER(7,2);
    V_RESULT_STATUS VARCHAR;
    V_RESULT_ID VARCHAR;
    V_ERROR_MSG VARCHAR;
    V_RUN_START TIMESTAMP_NTZ;
    V_RUN_END TIMESTAMP_NTZ;
    V_RULES_PROCESSED NUMBER DEFAULT 0;
    V_RULES_PASSED NUMBER DEFAULT 0;
    V_RULES_FAILED NUMBER DEFAULT 0;
    V_RULES_ERRORED NUMBER DEFAULT 0;
    
    C_RULES CURSOR FOR
        SELECT RULE_ID, RULE_NAME, RULE_TYPE, CRITICALITY, DB_NAME, TABLE_NM, COLUMN_NM, RULE_SQL, THRESHOLD_VALUE, RULE_DESCRIPTION
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_CONFIG
        WHERE IS_ACTIVE = TRUE
        ORDER BY TABLE_NM, RULE_ID;

    V_FULL_TABLE VARCHAR;
    V_SQL_STMT VARCHAR;
    V_ROW_COUNT_RS RESULTSET;
BEGIN
    V_RUN_ID := 'RUN_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS') || '_' || SUBSTR(UUID_STRING(), 1, 8);
    
    FOR REC IN C_RULES DO
        V_RULE_ID := REC.RULE_ID;
        V_RULE_NAME := REC.RULE_NAME;
        V_RULE_TYPE := REC.RULE_TYPE;
        V_CRITICALITY := REC.CRITICALITY;
        V_DB_NAME := REC.DB_NAME;
        V_TABLE_NM := REC.TABLE_NM;
        V_COLUMN_NM := REC.COLUMN_NM;
        V_RULE_SQL := REC.RULE_SQL;
        V_THRESHOLD := REC.THRESHOLD_VALUE;
        V_RULE_DESCRIPTION := REC.RULE_DESCRIPTION;
        V_RUN_START := CURRENT_TIMESTAMP();
        V_ERROR_MSG := NULL;
        V_ACTUAL_VALUE := NULL;
        V_TOTAL_ROWS := 0;
        V_FAILED_COUNT := 0;
        V_PASS_PCT := 100.00;
        V_RESULT_STATUS := 'PASS';
        V_FULL_TABLE := V_DB_NAME || '.' || V_TABLE_NM;
        
        BEGIN
            -- Get total row count for the table
            V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE;
            V_ROW_COUNT_RS := (EXECUTE IMMEDIATE :V_SQL_STMT);
            LET C1 CURSOR FOR V_ROW_COUNT_RS;
            FOR ROW1 IN C1 DO
                V_TOTAL_ROWS := ROW1.CNT;
            END FOR;
            
            IF (V_RULE_SQL = 'ROW_COUNT') THEN
                V_ACTUAL_VALUE := V_TOTAL_ROWS;
                V_FAILED_COUNT := 0;
                V_PASS_PCT := 100.00;
                V_RESULT_STATUS := 'PASS';
            ELSE
                -- Build SQL based on rule type
                IF (V_RULE_TYPE = 'SYSTEM_DMF' AND V_RULE_SQL LIKE 'NULL_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NULL';
                ELSEIF (V_RULE_TYPE = 'SYSTEM_DMF' AND V_RULE_SQL LIKE 'DUPLICATE_COUNT%') THEN
                    V_SQL_STMT := 'SELECT (COUNT(*) - COUNT(DISTINCT ' || :V_COLUMN_NM || ')) AS CNT FROM ' || :V_FULL_TABLE;
                ELSEIF (V_RULE_SQL LIKE 'INVALID_EMAIL_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND NOT ' || :V_COLUMN_NM || ' RLIKE ''^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,}$''';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_PHONE_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND NOT ' || :V_COLUMN_NM || ' RLIKE ''^[0-9]{10}$''';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_IFSC_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND NOT ' || :V_COLUMN_NM || ' RLIKE ''^[A-Z]{4}[0-9]{7}$''';
                ELSEIF (V_RULE_SQL LIKE 'UNREASONABLE_DOB_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND (YEAR(' || :V_COLUMN_NM || ') > 2025 OR YEAR(' || :V_COLUMN_NM || ') < 1900)';
                ELSEIF (V_RULE_SQL LIKE 'NEGATIVE_VALUE_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' < 0';
                ELSEIF (V_RULE_SQL LIKE 'ZERO_OR_NEGATIVE_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' <= 0';
                ELSEIF (V_RULE_SQL LIKE 'CREDIT_SCORE_OUT_OF_RANGE_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND (' || :V_COLUMN_NM || ' < 300 OR ' || :V_COLUMN_NM || ' > 850)';
                ELSEIF (V_RULE_SQL LIKE 'APPROVED_EXCEEDS_REQUESTED_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE APPROVED_AMOUNT IS NOT NULL AND APPROVED_AMOUNT > REQUESTED_AMOUNT';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_KYC_STATUS_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND ' || :V_COLUMN_NM || ' NOT IN (''VERIFIED'',''PENDING'',''REJECTED'')';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_ACCOUNT_STATUS_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND ' || :V_COLUMN_NM || ' NOT IN (''ACTIVE'',''DORMANT'',''CLOSED'')';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_ACCOUNT_TYPE_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND ' || :V_COLUMN_NM || ' NOT IN (''SAVINGS'',''CURRENT'',''LOAN'')';
                ELSEIF (V_RULE_SQL LIKE 'NON_INR_CURRENCY_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND ' || :V_COLUMN_NM || ' != ''INR''';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_TXN_TYPE_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND ' || :V_COLUMN_NM || ' NOT IN (''DEBIT'',''CREDIT'')';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_TXN_STATUS_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND ' || :V_COLUMN_NM || ' NOT IN (''SUCCESS'',''FAILED'',''PENDING'')';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_LOAN_TYPE_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND ' || :V_COLUMN_NM || ' NOT IN (''HOME'',''CAR'',''PERSONAL'',''EDUCATION'',''BUSINESS'')';
                ELSEIF (V_RULE_SQL LIKE 'INVALID_APP_STATUS_COUNT%') THEN
                    V_SQL_STMT := 'SELECT COUNT(*) AS CNT FROM ' || :V_FULL_TABLE || ' WHERE ' || :V_COLUMN_NM || ' IS NOT NULL AND ' || :V_COLUMN_NM || ' NOT IN (''APPROVED'',''PENDING'',''REJECTED'')';
                END IF;
                
                -- Execute the rule SQL
                LET RS RESULTSET := (EXECUTE IMMEDIATE :V_SQL_STMT);
                LET C2 CURSOR FOR RS;
                FOR ROW2 IN C2 DO
                    V_ACTUAL_VALUE := ROW2.CNT;
                END FOR;
                
                V_FAILED_COUNT := V_ACTUAL_VALUE;
                
                IF (V_TOTAL_ROWS > 0) THEN
                    V_PASS_PCT := ROUND(((V_TOTAL_ROWS - V_FAILED_COUNT) / V_TOTAL_ROWS) * 100, 2);
                ELSE
                    V_PASS_PCT := 100.00;
                END IF;
                
                IF (V_ACTUAL_VALUE > V_THRESHOLD) THEN
                    V_RESULT_STATUS := 'FAIL';
                    V_RULES_FAILED := V_RULES_FAILED + 1;
                ELSE
                    V_RESULT_STATUS := 'PASS';
                    V_RULES_PASSED := V_RULES_PASSED + 1;
                END IF;
            END IF;
            
            IF (V_RULE_SQL = 'ROW_COUNT') THEN
                V_RULES_PASSED := V_RULES_PASSED + 1;
            END IF;
            
            V_RUN_END := CURRENT_TIMESTAMP();
            V_RESULT_ID := 'RES_' || :V_RULE_ID || '_' || SUBSTR(UUID_STRING(), 1, 8);
            
            -- Log to DQ_RUN_CONTROL
            INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_RUN_CONTROL 
            (RUN_ID, RULE_ID, RUN_START_TIME, RUN_END_TIME, RULE_EXEC_RESULT, RULE_OUTPUT_VALUE, RUN_STATUS, TRIGGERED_BY, ERROR_MESSAGE)
            VALUES (:V_RUN_ID, :V_RULE_ID, :V_RUN_START, :V_RUN_END, :V_RESULT_STATUS, :V_ACTUAL_VALUE::VARCHAR, 'COMPLETED', :P_TRIGGERED_BY, NULL);
            
            -- Log to DQ_RULE_RESULTS
            INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS
            (RESULT_ID, RUN_ID, RULE_ID, DB_NAME, TABLE_NAME, COLUMN_NAME, RULE_NAME, RULE_TYPE,
             EXPECTED_VALUE, ACTUAL_VALUE, FAILED_RECORD_COUNT, TOTAL_RECORD_COUNT, PASS_PERCENTAGE, RESULT_STATUS, SEVERITY)
            VALUES (:V_RESULT_ID, :V_RUN_ID, :V_RULE_ID, :V_DB_NAME, :V_TABLE_NM, :V_COLUMN_NM, :V_RULE_NAME, :V_RULE_TYPE,
                    :V_THRESHOLD::VARCHAR, :V_ACTUAL_VALUE::VARCHAR, :V_FAILED_COUNT, :V_TOTAL_ROWS, :V_PASS_PCT, :V_RESULT_STATUS, :V_CRITICALITY);
            
            V_RULES_PROCESSED := V_RULES_PROCESSED + 1;
            
        EXCEPTION
            WHEN OTHER THEN
                V_ERROR_MSG := SQLERRM;
                V_RUN_END := CURRENT_TIMESTAMP();
                V_RULES_ERRORED := V_RULES_ERRORED + 1;
                V_RULES_PROCESSED := V_RULES_PROCESSED + 1;
                
                INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_RUN_CONTROL 
                (RUN_ID, RULE_ID, RUN_START_TIME, RUN_END_TIME, RULE_EXEC_RESULT, RULE_OUTPUT_VALUE, RUN_STATUS, TRIGGERED_BY, ERROR_MESSAGE)
                VALUES (:V_RUN_ID, :V_RULE_ID, :V_RUN_START, :V_RUN_END, 'ERROR', NULL, 'FAILED', :P_TRIGGERED_BY, :V_ERROR_MSG);
        END;
    END FOR;
    
    RETURN 'DQ Framework Run Complete | RUN_ID: ' || V_RUN_ID || 
           ' | Rules Processed: ' || V_RULES_PROCESSED || 
           ' | Passed: ' || V_RULES_PASSED || 
           ' | Failed: ' || V_RULES_FAILED || 
           ' | Errors: ' || V_RULES_ERRORED;
END;
$$;

-- =============================================
-- Execute the framework
-- =============================================
-- CALL BANKING_DQ_DB.DQ_MONITORING.SP_RUN_DQ_FRAMEWORK('MANUAL_TEST');
