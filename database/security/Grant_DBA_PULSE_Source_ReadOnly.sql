/*
    DBA Pulse source SQL read-only permissions

    Purpose
    -------
    Grants the minimum permissions required by the DBA Pulse Query Catalog:

      inventory   : sys.databases, sys.servers, SERVERPROPERTY, sys.dm_os_sys_info
      backup      : msdb.dbo.backupset
      capacity    : sys.master_files, sys.dm_os_volume_stats
      jobs        : msdb SQL Agent history/activity metadata
      Always On   : availability catalog views and HADR DMVs
      performance : request/session DMVs, SQL text, wait stats, system_health XE

    Scope
    -----
    Run this script on each monitored SOURCE SQL Server instance.
    It does not create tables, views, procedures, jobs, triggers, or XE sessions.
    It does not grant sysadmin, db_owner, ALTER SERVER STATE, or any write access.

    The login must already exist. This script creates only database users in
    master and msdb when they are missing.

    Version behavior
    ----------------
      SQL Server 2019 and earlier : VIEW SERVER STATE
      SQL Server 2022+            : VIEW SERVER PERFORMANCE STATE

    SQL Agent note
    --------------
    The direct SELECT grants below are intentionally limited to the objects
    read by queries/jobs/job-status.sql. They do not grant job execution,
    start/stop, retry, edit, or delete permissions.

    Security note
    -------------
    The performance queries return login name, host/application name and a
    limited SQL text preview/hash. The Collector must use a dedicated monitor
    credential and must not use sysadmin.
*/

USE [master];
GO

IF SUSER_ID(N'DBA_PULSE') IS NULL
    THROW 51000, 'Login [DBA_PULSE] does not exist. Create the login separately; this script does not manage passwords.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'DBA_PULSE') IS NULL
    CREATE USER [DBA_PULSE] FOR LOGIN [DBA_PULSE];
GO

GRANT CONNECT SQL TO [DBA_PULSE];

/*
   VIEW ANY DEFINITION is required for complete instance metadata visibility,
   including sys.master_files and Always On catalog metadata. It also implies
   the ability to see database metadata; it does not grant data access.
*/
GRANT VIEW ANY DEFINITION TO [DBA_PULSE];

/* SQL Server 2019 and earlier versus SQL Server 2022+. */
IF TRY_CONVERT(int, SERVERPROPERTY(N'ProductMajorVersion')) >= 16
    EXEC(N'GRANT VIEW SERVER PERFORMANCE STATE TO [DBA_PULSE];');
ELSE
    GRANT VIEW SERVER STATE TO [DBA_PULSE];
GO

/* Explicit SELECT grants for the master-scoped Query Catalog objects. */
GRANT SELECT ON OBJECT::[sys].[databases] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[servers] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[master_files] TO [DBA_PULSE];

GRANT SELECT ON OBJECT::[sys].[dm_os_sys_info] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[dm_exec_requests] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[dm_exec_sessions] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[dm_exec_sql_text] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[dm_os_volume_stats] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[dm_os_wait_stats] TO [DBA_PULSE];

GRANT SELECT ON OBJECT::[sys].[availability_groups] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[availability_replicas] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[dm_hadr_availability_replica_states] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[dm_hadr_database_replica_states] TO [DBA_PULSE];

GRANT SELECT ON OBJECT::[sys].[dm_xe_sessions] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[sys].[dm_xe_session_targets] TO [DBA_PULSE];
GO

USE [msdb];
GO

IF DATABASE_PRINCIPAL_ID(N'DBA_PULSE') IS NULL
    CREATE USER [DBA_PULSE] FOR LOGIN [DBA_PULSE];
GO

/* Latest backup metadata used by queries/backup/last-backups.sql. */
GRANT SELECT ON OBJECT::[dbo].[backupset] TO [DBA_PULSE];

/* SQL Agent job status, history, current activity and SQL Server sessions. */
GRANT SELECT ON OBJECT::[dbo].[sysjobs] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[dbo].[sysjobhistory] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[dbo].[sysjobactivity] TO [DBA_PULSE];
GRANT SELECT ON OBJECT::[dbo].[syssessions] TO [DBA_PULSE];
GO

/*
    Verification queries (read-only; optional)

    -- Run as DBA_PULSE:
    SELECT HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW ANY DEFINITION');
    SELECT HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW SERVER STATE');
    SELECT HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW SERVER PERFORMANCE STATE');
    SELECT TOP (1) * FROM master.sys.dm_os_sys_info;
    SELECT TOP (1) * FROM msdb.dbo.backupset;
*/
