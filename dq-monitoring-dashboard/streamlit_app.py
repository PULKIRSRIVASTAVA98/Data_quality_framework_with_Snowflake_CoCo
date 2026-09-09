import os
import streamlit as st

st.set_page_config(page_title="DQ Monitoring Dashboard", page_icon="📊", layout="wide")

conn = st.connection("snowflake", ttl=os.getenv("SNOWFLAKE_CONNECTION_TTL"))


@st.cache_data(ttl=300)
def get_latest_run_id():
    df = conn.query("""
        SELECT RUN_ID, MAX(RUN_END_TIME) AS RUN_TIME
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RUN_CONTROL
        WHERE RUN_STATUS = 'COMPLETED'
        GROUP BY RUN_ID
        ORDER BY RUN_TIME DESC
        LIMIT 1
    """)
    if len(df) > 0:
        return df.iloc[0]["RUN_ID"]
    return None


@st.cache_data(ttl=300)
def get_all_run_ids():
    return conn.query("""
        SELECT DISTINCT RUN_ID,
               MIN(RUN_START_TIME) AS RUN_START,
               MAX(RUN_END_TIME) AS RUN_END
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RUN_CONTROL
        GROUP BY RUN_ID
        ORDER BY RUN_START DESC
        LIMIT 20
    """)


@st.cache_data(ttl=300)
def get_run_summary(run_id):
    return conn.query(f"""
        SELECT
            COUNT(*) AS TOTAL_RULES,
            SUM(CASE WHEN RESULT_STATUS = 'PASS' THEN 1 ELSE 0 END) AS PASSED,
            SUM(CASE WHEN RESULT_STATUS = 'FAIL' THEN 1 ELSE 0 END) AS FAILED,
            ROUND(AVG(PASS_PERCENTAGE), 2) AS AVG_PASS_PCT
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS
        WHERE RUN_ID = '{run_id}'
    """)


@st.cache_data(ttl=300)
def get_results_by_table(run_id):
    return conn.query(f"""
        SELECT
            TABLE_NAME,
            COUNT(*) AS TOTAL_RULES,
            SUM(CASE WHEN RESULT_STATUS = 'PASS' THEN 1 ELSE 0 END) AS PASSED,
            SUM(CASE WHEN RESULT_STATUS = 'FAIL' THEN 1 ELSE 0 END) AS FAILED,
            ROUND(AVG(PASS_PERCENTAGE), 2) AS AVG_PASS_PCT
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS
        WHERE RUN_ID = '{run_id}'
        GROUP BY TABLE_NAME
        ORDER BY AVG_PASS_PCT ASC
    """)


@st.cache_data(ttl=300)
def get_rule_details(run_id):
    return conn.query(f"""
        SELECT
            TABLE_NAME, RULE_NAME, COLUMN_NAME, RULE_TYPE,
            RESULT_STATUS, SEVERITY, FAILED_RECORD_COUNT,
            TOTAL_RECORD_COUNT, PASS_PERCENTAGE
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS
        WHERE RUN_ID = '{run_id}'
        ORDER BY
            CASE RESULT_STATUS WHEN 'FAIL' THEN 1 ELSE 2 END,
            TABLE_NAME, RULE_NAME
    """)


@st.cache_data(ttl=300)
def get_trend_data():
    return conn.query("""
        SELECT
            R.RUN_ID,
            MIN(C.RUN_START_TIME) AS RUN_TIME,
            COUNT(*) AS TOTAL_RULES,
            SUM(CASE WHEN R.RESULT_STATUS = 'PASS' THEN 1 ELSE 0 END) AS PASSED,
            SUM(CASE WHEN R.RESULT_STATUS = 'FAIL' THEN 1 ELSE 0 END) AS FAILED,
            ROUND(AVG(R.PASS_PERCENTAGE), 2) AS AVG_PASS_PCT
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS R
        JOIN BANKING_DQ_DB.DQ_MONITORING.DQ_RUN_CONTROL C
            ON R.RUN_ID = C.RUN_ID AND R.RULE_ID = C.RULE_ID
        GROUP BY R.RUN_ID
        ORDER BY RUN_TIME DESC
        LIMIT 10
    """)


@st.cache_data(ttl=300)
def get_dimension_summary(run_id):
    return conn.query(f"""
        SELECT
            CFG.RULE_DIMENSION::VARCHAR AS DIMENSION,
            COUNT(*) AS TOTAL,
            SUM(CASE WHEN R.RESULT_STATUS = 'PASS' THEN 1 ELSE 0 END) AS PASSED,
            SUM(CASE WHEN R.RESULT_STATUS = 'FAIL' THEN 1 ELSE 0 END) AS FAILED
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS R
        JOIN BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_CONFIG CFG
            ON R.RULE_ID = CFG.RULE_ID
        WHERE R.RUN_ID = '{run_id}'
        GROUP BY CFG.RULE_DIMENSION
        ORDER BY FAILED DESC
    """)


def clear_cache():
    get_latest_run_id.clear()
    get_all_run_ids.clear()
    get_run_summary.clear()
    get_results_by_table.clear()
    get_rule_details.clear()
    get_trend_data.clear()
    get_dimension_summary.clear()


# --- Header ---
st.title("Data Quality Monitoring Dashboard")
st.caption("BANKING_DQ_DB — Real-time DQ framework results")

# --- Sidebar ---
with st.sidebar:
    st.header("Controls")
    st.button("Refresh Data", on_click=clear_cache)

    runs_df = get_all_run_ids()
    if len(runs_df) > 0:
        run_options = runs_df["RUN_ID"].tolist()
        selected_run = st.selectbox("Select Run", run_options)
    else:
        st.warning("No DQ runs found.")
        st.stop()

# --- KPI Metrics ---
summary = get_run_summary(selected_run)
if len(summary) > 0:
    row = summary.iloc[0]
    total = int(row["TOTAL_RULES"])
    passed = int(row["PASSED"])
    failed = int(row["FAILED"])
    avg_pct = float(row["AVG_PASS_PCT"])

    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Total Rules", total)
    col2.metric("Passed", passed)
    col3.metric("Failed", failed)
    col4.metric("Avg Pass %", f"{avg_pct}%")

    if avg_pct >= 95:
        st.success(f"Overall DQ Score: {avg_pct}% — Excellent")
    elif avg_pct >= 80:
        st.warning(f"Overall DQ Score: {avg_pct}% — Needs Attention")
    else:
        st.error(f"Overall DQ Score: {avg_pct}% — Critical")

st.divider()

# --- Tabs ---
tab1, tab2, tab3, tab4 = st.tabs(["By Table", "Rule Details", "By Dimension", "Trend"])

with tab1:
    st.subheader("Pass Rate by Table")
    table_df = get_results_by_table(selected_run)
    if len(table_df) > 0:
        st.bar_chart(table_df.set_index("TABLE_NAME")["AVG_PASS_PCT"])
        st.dataframe(table_df, use_container_width=True, hide_index=True)

with tab2:
    st.subheader("Rule-Level Results")
    details_df = get_rule_details(selected_run)
    if len(details_df) > 0:
        filter_status = st.multiselect(
            "Filter by Status", ["PASS", "FAIL"], default=["PASS", "FAIL"]
        )
        filtered = details_df[details_df["RESULT_STATUS"].isin(filter_status)]
        st.dataframe(
            filtered.style.applymap(
                lambda v: "background-color: #ffcccc" if v == "FAIL" else "",
                subset=["RESULT_STATUS"],
            ),
            use_container_width=True,
            hide_index=True,
        )

with tab3:
    st.subheader("Results by Quality Dimension")
    dim_df = get_dimension_summary(selected_run)
    if len(dim_df) > 0:
        st.bar_chart(dim_df.set_index("DIMENSION")[["PASSED", "FAILED"]])
        st.dataframe(dim_df, use_container_width=True, hide_index=True)

with tab4:
    st.subheader("DQ Score Trend (Last 10 Runs)")
    trend_df = get_trend_data()
    if len(trend_df) > 0:
        trend_df = trend_df.sort_values("RUN_TIME")
        st.line_chart(trend_df.set_index("RUN_TIME")["AVG_PASS_PCT"])
        st.dataframe(trend_df, use_container_width=True, hide_index=True)
