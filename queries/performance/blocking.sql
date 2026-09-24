SELECT
    r.session_id AS session_id,
    r.blocking_session_id AS blocking_session_id,
    DB_NAME(r.database_id) AS database_name,
    r.wait_type AS wait_type,
    CONVERT(bigint, r.wait_time) AS wait_duration_ms,
    r.command AS command_name,
    s.host_name AS host_name,
    s.program_name AS application_name,
    s.login_name AS login_name,
    CONVERT(varchar(64), HASHBYTES('SHA2_256', CONVERT(nvarchar(max), ISNULL(st.text, N''))), 2) AS sql_text_hash,
    LEFT(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), ISNULL(st.text, N'')), CHAR(13), N' '), CHAR(10), N' '), CHAR(9), N' '), 1500) AS sql_text_preview
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.blocking_session_id > 0
  AND r.session_id > 50
  AND s.is_user_process = 1;
