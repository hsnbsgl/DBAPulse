/* Read-only and lab-safe: returns NotConfigured when Always On is unavailable. */
IF CAST(ISNULL(SERVERPROPERTY(N'IsHadrEnabled'), 0) AS int) = 1
   AND EXISTS (SELECT 1 FROM sys.availability_groups)
BEGIN
    SELECT
        ag.name AS availability_group_name,
        ar.replica_server_name,
        ars.role_desc,
        ars.operational_state_desc,
        ars.connected_state_desc,
        ars.synchronization_health_desc,
        drs.database_id,
        DB_NAME(drs.database_id) AS database_name,
        drs.synchronization_state_desc,
        drs.database_state_desc,
        CAST(drs.is_suspended AS bit) AS is_suspended,
        drs.suspend_reason_desc AS suspend_reason,
        CAST(drs.log_send_queue_size / 1024.0 AS decimal(19,2)) AS log_send_queue_mb,
        CAST(drs.redo_queue_size / 1024.0 AS decimal(19,2)) AS redo_queue_mb,
        CAST(drs.log_send_rate / 1024.0 AS decimal(19,2)) AS log_send_rate_mb,
        CAST(drs.redo_rate / 1024.0 AS decimal(19,2)) AS redo_rate_mb,
        drs.last_commit_time AS last_commit_time_source
    FROM sys.availability_groups AS ag
    INNER JOIN sys.availability_replicas AS ar ON ar.group_id = ag.group_id
    LEFT JOIN sys.dm_hadr_availability_replica_states AS ars ON ars.replica_id = ar.replica_id
    LEFT JOIN sys.dm_hadr_database_replica_states AS drs ON drs.group_id = ag.group_id AND drs.replica_id = ar.replica_id
    ORDER BY ag.name, ar.replica_server_name, database_name;
END
ELSE
BEGIN
    SELECT
        CAST('NotConfigured' AS nvarchar(32)) AS status,
        CAST(NULL AS nvarchar(128)) AS availability_group_name,
        CAST(NULL AS nvarchar(128)) AS replica_server_name;
END;
