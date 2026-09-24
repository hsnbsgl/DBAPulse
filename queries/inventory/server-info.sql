/* Read-only: server identity, engine details, and SQL Server start time. */
SELECT
    CAST(SERVERPROPERTY(N'MachineName') AS nvarchar(128)) AS machine_name,
    CAST(SERVERPROPERTY(N'ServerName') AS nvarchar(128)) AS server_name,
    COALESCE(NULLIF(CAST(SERVERPROPERTY(N'InstanceName') AS nvarchar(128)), N''), N'MSSQLSERVER') AS instance_name,
    CAST(SERVERPROPERTY(N'ProductVersion') AS nvarchar(128)) AS product_version,
    CAST(SERVERPROPERTY(N'ProductLevel') AS nvarchar(128)) AS product_level,
    CAST(SERVERPROPERTY(N'Edition') AS nvarchar(256)) AS edition,
    osi.sqlserver_start_time,
    DATEDIFF_BIG(SECOND, osi.sqlserver_start_time, SYSUTCDATETIME()) AS uptime_seconds
FROM sys.dm_os_sys_info AS osi;
