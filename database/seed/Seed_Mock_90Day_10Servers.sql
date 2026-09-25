/*
   DBA Pulse lab-only mock data: 10 servers x 90 days.

   This is a seed script, not a migration. Keep it outside database/migrations.
   It inserts only the isolated DBAPULSE-90D-* mock context and is idempotent.
   It must never be used against a production DBA_PULSE database.
*/
USE DBA_PULSE;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = N'DBAPULSE-90D-SQL01')
BEGIN
    PRINT N'DBAPULSE 90-day mock data already exists; no rows inserted.';
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @EndUtc datetime2(3) = DATEADD(HOUR, -1, SYSUTCDATETIME());
    DECLARE @SeedMarker nvarchar(64) = N'DBAPULSE_PHASE8_90D_MOCK';

    CREATE TABLE #Calendar
    (
        DayOffset int NOT NULL PRIMARY KEY,
        CollectedAtUtc datetime2(3) NOT NULL
    );

    ;WITH N AS
    (
        SELECT TOP (90)
            CONVERT(int, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1) AS DayOffset
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    )
    INSERT #Calendar (DayOffset, CollectedAtUtc)
    SELECT DayOffset, DATEADD(DAY, -DayOffset, @EndUtc)
    FROM N;

    CREATE TABLE #Servers
    (
        MockNo int NOT NULL PRIMARY KEY,
        ServerId int NOT NULL,
        ServerName nvarchar(256) NOT NULL
    );

    INSERT dbo.Servers (ServerName, InstanceName, SqlVersion, Edition, TimeZoneId, LastSeenAtUtc, IsActive)
    SELECT CONCAT(N'DBAPULSE-90D-SQL', RIGHT(CONCAT(N'0', CONVERT(varchar(2), v.MockNo)), 2)),
           CONCAT(N'DBAPULSE-90D-SQL', RIGHT(CONCAT(N'0', CONVERT(varchar(2), v.MockNo)), 2), N'\\SQL',
                  CASE v.MockNo % 3 WHEN 0 THEN N'2025' WHEN 1 THEN N'2022' ELSE N'2019' END),
           CASE v.MockNo % 3 WHEN 0 THEN N'SQL Server 2025 (Mock)' WHEN 1 THEN N'SQL Server 2022 (Mock)' ELSE N'SQL Server 2019 (Mock)' END,
           N'Developer (Mock)', N'Europe/Istanbul', @EndUtc, 1
    FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)) v(MockNo);

    INSERT #Servers (MockNo, ServerId, ServerName)
    SELECT v.MockNo, s.Id, s.ServerName
    FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)) v(MockNo)
    JOIN dbo.Servers s ON s.ServerName = CONCAT(N'DBAPULSE-90D-SQL', RIGHT(CONCAT(N'0', CONVERT(varchar(2), v.MockNo)), 2));

    CREATE TABLE #DatabaseSeed
    (
        MockNo int NOT NULL,
        DbNo int NOT NULL,
        DatabaseName nvarchar(256) NOT NULL,
        RecoveryModel nvarchar(60) NOT NULL,
        PRIMARY KEY (MockNo, DbNo)
    );

    INSERT #DatabaseSeed (MockNo, DbNo, DatabaseName, RecoveryModel)
    SELECT s.MockNo, d.DbNo,
           CONCAT(N'DBAPULSE_90D_', RIGHT(CONCAT(N'0', CONVERT(varchar(2), s.MockNo)), 2), N'_', d.Name),
           d.RecoveryModel
    FROM #Servers s
    CROSS JOIN (VALUES (1, N'CORE', N'FULL'), (2, N'DWH', N'SIMPLE'), (3, N'REPORTING', N'FULL')) d(DbNo, Name, RecoveryModel);

    INSERT dbo.Databases (ServerId, DatabaseName, RecoveryModel, DatabaseStatus, LastSeenAtUtc, IsActive)
    SELECT s.ServerId, d.DatabaseName, d.RecoveryModel, N'ONLINE', @EndUtc, 1
    FROM #DatabaseSeed d
    JOIN #Servers s ON s.MockNo = d.MockNo;

    CREATE TABLE #Databases
    (
        MockNo int NOT NULL,
        DbNo int NOT NULL,
        DatabaseId int NOT NULL,
        DatabaseName nvarchar(256) NOT NULL,
        RecoveryModel nvarchar(60) NOT NULL,
        PRIMARY KEY (MockNo, DbNo)
    );

    INSERT #Databases (MockNo, DbNo, DatabaseId, DatabaseName, RecoveryModel)
    SELECT d.MockNo, d.DbNo, db.Id, d.DatabaseName, d.RecoveryModel
    FROM #DatabaseSeed d
    JOIN #Servers s ON s.MockNo = d.MockNo
    JOIN dbo.Databases db ON db.ServerId = s.ServerId AND db.DatabaseName = d.DatabaseName;

    IF (SELECT COUNT(*) FROM #Servers) <> 10 OR (SELECT COUNT(*) FROM #Databases) <> 30
        THROW 51000, '90-day mock seed did not create the expected server/database set.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.BackupPolicies WHERE PolicyName = N'90-Day Mock Lab Policy')
        INSERT dbo.BackupPolicies (PolicyName, FullBackupMaxAgeHours, DifferentialBackupMaxAgeHours, LogBackupMaxAgeMinutes, WarningPercentage, IsEnabled)
        VALUES (N'90-Day Mock Lab Policy', 24, NULL, 60, 80, 1);

    IF NOT EXISTS (SELECT 1 FROM dbo.WaitTypeExclusions WHERE WaitType = N'90D_MOCK_BACKGROUND_WAIT')
        INSERT dbo.WaitTypeExclusions (WaitType, Reason, IsEnabled)
        VALUES (N'90D_MOCK_BACKGROUND_WAIT', N'90-day mock background wait excluded from management views.', 1);

    IF NOT EXISTS (SELECT 1 FROM dbo.AnomalyPolicies WHERE MetricType = N'90D_MockDuration')
        INSERT dbo.AnomalyPolicies (MetricType, WarningPercentile, CriticalPercentile, WarningModifiedZ, CriticalModifiedZ, MinObservedValue, IsEnabled)
        VALUES (N'90D_MockDuration', .95, .99, 3, 6, 1, 1);

    CREATE TABLE #Runs
    (
        RunId bigint NOT NULL,
        MockNo int NOT NULL,
        DayOffset int NOT NULL,
        PRIMARY KEY (MockNo, DayOffset)
    );

    CREATE TABLE #RunSeed
    (
        MockNo int NOT NULL,
        DayOffset int NOT NULL,
        StartedAtUtc datetime2(3) NOT NULL,
        PRIMARY KEY (MockNo, DayOffset)
    );

    INSERT #RunSeed (MockNo, DayOffset, StartedAtUtc)
    SELECT s.MockNo, c.DayOffset, DATEADD(SECOND, s.MockNo * 13 + c.DayOffset % 41, c.CollectedAtUtc)
    FROM #Servers s CROSS JOIN #Calendar c;

    INSERT dbo.CollectionRuns (StartedAtUtc, FinishedAtUtc, Status, DurationMs)
    SELECT r.StartedAtUtc,
           DATEADD(SECOND, 12 + (s.MockNo % 5), r.StartedAtUtc),
           CASE WHEN s.MockNo = 4 AND r.DayOffset IN (27, 63) THEN N'PartialSuccess' ELSE N'Success' END,
           12000 + s.MockNo * 100 + r.DayOffset % 41
    FROM #RunSeed r JOIN #Servers s ON s.MockNo = r.MockNo;

    INSERT #Runs (RunId, MockNo, DayOffset)
    SELECT cr.Id, r.MockNo, r.DayOffset
    FROM #RunSeed r JOIN dbo.CollectionRuns cr ON cr.StartedAtUtc = r.StartedAtUtc;

    INSERT dbo.CollectionErrors (CollectionRunId, QueryName, ServerName, ErrorMessage, CreatedAtUtc)
    SELECT r.RunId, N'performance/wait-stats.sql', s.ServerName,
           N'Mock permission failure for failure-semantics validation.', DATEADD(SECOND, 15, c.CollectedAtUtc)
    FROM #Runs r
    JOIN #Servers s ON s.MockNo = r.MockNo
    JOIN #Calendar c ON c.DayOffset = r.DayOffset
    WHERE r.MockNo = 4 AND r.DayOffset IN (27, 63);

    INSERT dbo.ServerSnapshots (CollectionRunId, ServerId, CollectedAtUtc, UptimeSeconds)
    SELECT r.RunId, s.ServerId, c.CollectedAtUtc, CONVERT(bigint, (90 - r.DayOffset) * 86400 + s.MockNo * 3600)
    FROM #Runs r JOIN #Servers s ON s.MockNo = r.MockNo JOIN #Calendar c ON c.DayOffset = r.DayOffset;

    INSERT dbo.DatabaseSnapshots (CollectionRunId, DatabaseId, CollectedAtUtc, DatabaseStatus, UserAccess, CompatibilityLevel, IsReadOnly, IsEncrypted)
    SELECT r.RunId, d.DatabaseId, c.CollectedAtUtc, N'ONLINE', N'MULTI_USER',
           CASE WHEN d.DbNo = 3 THEN 160 ELSE 150 + (s.MockNo % 3) * 5 END, 0,
           CASE WHEN d.DbNo = 1 AND s.MockNo % 4 = 0 THEN 1 ELSE 0 END
    FROM #Runs r
    JOIN #Servers s ON s.MockNo = r.MockNo
    JOIN #Calendar c ON c.DayOffset = r.DayOffset
    JOIN #Databases d ON d.MockNo = r.MockNo;

    INSERT dbo.BackupSnapshots
    (
        CollectionRunId, ServerId, DatabaseId, DatabaseName, CollectedAtUtc, BackupType,
        BackupStartAtSource, BackupFinishAtSource, BackupSizeMb, CompressedBackupSizeMb, IsCopyOnly, BackupDurationSeconds
    )
    SELECT r.RunId, s.ServerId, d.DatabaseId, d.DatabaseName, c.CollectedAtUtc, N'Full',
           DATEADD(HOUR, 3, DATEADD(MINUTE, -42 - d.DbNo * 4, c.CollectedAtUtc)),
           DATEADD(HOUR, 3, DATEADD(MINUTE, -d.DbNo * 4, c.CollectedAtUtc)),
           CONVERT(decimal(19,2), 90000 + s.MockNo * 2500 + d.DbNo * 800),
           CONVERT(decimal(19,2), 36000 + s.MockNo * 1000 + d.DbNo * 300),
           0, 2400 + s.MockNo * 30 + d.DbNo * 15
    FROM #Runs r JOIN #Servers s ON s.MockNo = r.MockNo JOIN #Calendar c ON c.DayOffset = r.DayOffset
    JOIN #Databases d ON d.MockNo = r.MockNo
    WHERE r.DayOffset % 7 = 0
    UNION ALL
    SELECT r.RunId, s.ServerId, d.DatabaseId, d.DatabaseName, c.CollectedAtUtc, N'Differential',
           DATEADD(HOUR, 3, DATEADD(MINUTE, -12 - d.DbNo, c.CollectedAtUtc)),
           DATEADD(HOUR, 3, DATEADD(MINUTE, -d.DbNo, c.CollectedAtUtc)),
           CONVERT(decimal(19,2), 15000 + s.MockNo * 500 + d.DbNo * 250),
           CONVERT(decimal(19,2), 6000 + s.MockNo * 200 + d.DbNo * 100),
           0, 600 + d.DbNo * 10
    FROM #Runs r JOIN #Servers s ON s.MockNo = r.MockNo JOIN #Calendar c ON c.DayOffset = r.DayOffset
    JOIN #Databases d ON d.MockNo = r.MockNo
    WHERE r.DayOffset % 3 = 0 AND d.RecoveryModel <> N'SIMPLE'
    UNION ALL
    SELECT r.RunId, s.ServerId, d.DatabaseId, d.DatabaseName, c.CollectedAtUtc, N'Log',
           DATEADD(HOUR, 3, DATEADD(MINUTE, -4, c.CollectedAtUtc)),
           DATEADD(HOUR, 3, DATEADD(MINUTE, -3, c.CollectedAtUtc)),
           CONVERT(decimal(19,2), 800 + s.MockNo * 20 + d.DbNo * 10),
           CONVERT(decimal(19,2), 320 + s.MockNo * 8 + d.DbNo * 4),
           0, 60 + d.DbNo * 3
    FROM #Runs r JOIN #Servers s ON s.MockNo = r.MockNo JOIN #Calendar c ON c.DayOffset = r.DayOffset
    JOIN #Databases d ON d.MockNo = r.MockNo
    WHERE d.RecoveryModel <> N'SIMPLE';

    ;WITH JobSeed AS
    (
        SELECT * FROM (VALUES
            (1, N'90D-ETL-', N'90D Nightly ETL', 1),
            (2, N'90D-BACKUP-', N'90D Backup Verification', 1),
            (3, N'90D-INDEX-', N'90D Index Maintenance', 1)
        ) v(JobNo, JobPrefix, JobName, Enabled)
    )
    INSERT dbo.JobSnapshots
    (
        CollectionRunId, ServerId, CollectedAtUtc, JobId, JobName, Enabled, LastRunStatus,
        LastRunAtSource, LastRunDurationSeconds, LastRunMessage, IsRunning, CurrentStartAtSource,
        CurrentDurationSeconds, NextRunAtSource, FailureCount24Hours, FailureCount7Days,
        RepeatedFailure, AverageDurationSeconds, MaxDurationSeconds
    )
    SELECT r.RunId, s.ServerId, c.CollectedAtUtc,
           CONCAT(j.JobPrefix, RIGHT(CONCAT(N'0', CONVERT(varchar(2), s.MockNo)), 2)),
           j.JobName, j.Enabled,
           CASE WHEN j.JobNo = 1 AND s.MockNo IN (3, 7) AND r.DayOffset % 14 = 0 THEN N'Failed'
                WHEN j.JobNo = 3 AND r.DayOffset = 0 THEN N'Succeeded' ELSE N'Succeeded' END,
           DATEADD(HOUR, 3, DATEADD(MINUTE, -35 - j.JobNo * 3, c.CollectedAtUtc)),
           CASE WHEN j.JobNo = 1 AND s.MockNo IN (3, 7) AND r.DayOffset % 14 = 0 THEN 2100 + s.MockNo * 60
                ELSE 420 + j.JobNo * 80 + s.MockNo * 15 END,
           CASE WHEN j.JobNo = 1 AND s.MockNo IN (3, 7) AND r.DayOffset % 14 = 0 THEN N'Mock ETL validation step failed.' ELSE N'Mock job completed successfully.' END,
           CASE WHEN j.JobNo = 3 AND r.DayOffset = 0 THEN 1 ELSE 0 END,
           CASE WHEN j.JobNo = 3 AND r.DayOffset = 0 THEN DATEADD(HOUR, 3, DATEADD(MINUTE, -40, c.CollectedAtUtc)) ELSE NULL END,
           CASE WHEN j.JobNo = 3 AND r.DayOffset = 0 THEN 2400 + s.MockNo * 90 ELSE NULL END,
           DATEADD(HOUR, 3, DATEADD(HOUR, j.JobNo * 4, c.CollectedAtUtc)),
           CASE WHEN j.JobNo = 1 AND s.MockNo IN (3, 7) AND r.DayOffset % 14 = 0 THEN 1 ELSE 0 END,
           CASE WHEN j.JobNo = 1 AND s.MockNo IN (3, 7) AND r.DayOffset % 14 = 0 THEN 3 ELSE 0 END,
           CASE WHEN j.JobNo = 1 AND s.MockNo IN (3, 7) AND r.DayOffset % 14 = 0 THEN 1 ELSE 0 END,
           480 + j.JobNo * 75 + s.MockNo * 10,
           720 + j.JobNo * 120 + s.MockNo * 20
    FROM #Runs r JOIN #Servers s ON s.MockNo = r.MockNo JOIN #Calendar c ON c.DayOffset = r.DayOffset CROSS JOIN JobSeed j;

    INSERT dbo.AlwaysOnSnapshots
    (
        CollectionRunId, ServerId, CollectedAtUtc, AvailabilityGroupName, ReplicaServerName, RoleDescription,
        OperationalState, ConnectedState, SynchronizationHealth, DatabaseName, SynchronizationState,
        DatabaseState, IsSuspended, SuspendReason, LogSendQueueMb, RedoQueueMb, LogSendRateMb, RedoRateMb, LastCommitTimeSource
    )
    SELECT r.RunId, s.ServerId, c.CollectedAtUtc, N'AG_90D_CORE',
           CONCAT(s.ServerName, CASE WHEN replica.ReplicaNo = 1 THEN N'-PRIMARY' ELSE N'-SECONDARY' END),
           CASE WHEN replica.ReplicaNo = 1 THEN N'PRIMARY' ELSE N'SECONDARY' END,
           N'ONLINE',
           CASE WHEN replica.ReplicaNo = 2 AND s.MockNo IN (3, 7) AND r.DayOffset < 14 THEN N'DISCONNECTED' ELSE N'CONNECTED' END,
           CASE WHEN replica.ReplicaNo = 2 AND s.MockNo IN (3, 7) AND r.DayOffset < 14 THEN N'NOT_HEALTHY' ELSE N'HEALTHY' END,
           CONCAT(N'DBAPULSE_90D_', RIGHT(CONCAT(N'0', CONVERT(varchar(2), s.MockNo)), 2), N'_CORE'),
           CASE WHEN replica.ReplicaNo = 2 AND s.MockNo IN (3, 7) AND r.DayOffset < 14 THEN N'NOT_SYNCHRONIZING' ELSE N'SYNCHRONIZED' END,
           N'ONLINE',
           CASE WHEN replica.ReplicaNo = 2 AND s.MockNo IN (3, 7) AND r.DayOffset < 7 THEN 1 ELSE 0 END,
           CASE WHEN replica.ReplicaNo = 2 AND s.MockNo IN (3, 7) AND r.DayOffset < 7 THEN N'Mock secondary suspend state.' ELSE NULL END,
           CASE WHEN replica.ReplicaNo = 2 THEN 128 + s.MockNo * 8 + (89 - r.DayOffset) * 3 ELSE 0 END,
           CASE WHEN replica.ReplicaNo = 2 THEN 64 + s.MockNo * 4 + (89 - r.DayOffset) * 2 ELSE 0 END,
           CASE WHEN replica.ReplicaNo = 2 THEN 40 + s.MockNo ELSE 85 END,
           CASE WHEN replica.ReplicaNo = 2 THEN 20 + s.MockNo ELSE 90 END,
           DATEADD(HOUR, 3, DATEADD(MINUTE, CASE WHEN replica.ReplicaNo = 2 AND s.MockNo IN (3, 7) THEN -18 ELSE -1 END, c.CollectedAtUtc))
    FROM #Runs r JOIN #Servers s ON s.MockNo = r.MockNo JOIN #Calendar c ON c.DayOffset = r.DayOffset
    CROSS JOIN (VALUES (1),(2)) replica(ReplicaNo);

    INSERT dbo.CapacitySnapshots (CollectionRunId, ServerId, DatabaseId, DatabaseName, CollectedAtUtc, FileType, AllocatedSizeMb, FileCount)
    SELECT r.RunId, s.ServerId, d.DatabaseId, d.DatabaseName, c.CollectedAtUtc, f.FileType,
           CONVERT(decimal(19,2),
               CASE WHEN f.FileType = N'Data' THEN
                    (CASE d.DbNo WHEN 1 THEN 102400 WHEN 2 THEN 204800 WHEN 3 THEN 76800 END)
                    + (89 - r.DayOffset) * (s.MockNo * 35 + d.DbNo * 90)
                ELSE
                    (CASE d.DbNo WHEN 1 THEN 20480 WHEN 2 THEN 51200 WHEN 3 THEN 12288 END)
                    + (89 - r.DayOffset) * (s.MockNo * 7 + d.DbNo * 18)
                END),
           CASE WHEN f.FileType = N'Data' THEN 2 ELSE 1 END
    FROM #Runs r JOIN #Servers s ON s.MockNo = r.MockNo JOIN #Calendar c ON c.DayOffset = r.DayOffset
    JOIN #Databases d ON d.MockNo = r.MockNo CROSS JOIN (VALUES (N'Data'),(N'Log')) f(FileType);

    INSERT dbo.VolumeCapacitySnapshots (CollectionRunId, ServerId, VolumeId, CollectedAtUtc, TotalBytes, AvailableBytes)
    SELECT r.RunId, s.ServerId, CONCAT(N'90D-VOLUME-', RIGHT(CONCAT(N'0', CONVERT(varchar(2), s.MockNo)), 2)),
           c.CollectedAtUtc,
           CONVERT(bigint, 2048 + s.MockNo * 64) * CONVERT(bigint, 1073741824),
           CONVERT(bigint, 180 + s.MockNo * 8 + r.DayOffset * (2 + s.MockNo % 3)) * CONVERT(bigint, 1073741824)
    FROM #Runs r JOIN #Servers s ON s.MockNo = r.MockNo JOIN #Calendar c ON c.DayOffset = r.DayOffset;

    CREATE TABLE #Blocks
    (
        BlockingId bigint NOT NULL,
        MockNo int NOT NULL,
        DayOffset int NOT NULL,
        DatabaseId int NOT NULL
    );

    INSERT dbo.BlockingEvents
    (
        ServerId, DatabaseId, CapturedAtUtc, SessionId, BlockingSessionId, WaitType, WaitDurationMs,
        Command, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview
    )
    SELECT s.ServerId, d.DatabaseId, c.CollectedAtUtc, 5000 + s.MockNo, 6000 + s.MockNo,
           CASE WHEN s.MockNo % 2 = 0 THEN N'LCK_M_X' ELSE N'LCK_M_S' END,
           CONVERT(bigint, 5000 + (89 - c.DayOffset) * 900 + s.MockNo * 250), N'UPDATE',
           CONCAT(N'90D-APP-', RIGHT(CONCAT(N'0', CONVERT(varchar(2), s.MockNo)), 2)), N'DBA Pulse Mock API', N'mock_operator',
           CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-block-', s.MockNo)), 2),
           N'UPDATE dbo.DBA_Pulse_MockWorkload SET Value = Value + 1 WHERE Id = 1'
    FROM #Servers s JOIN #Calendar c ON c.DayOffset % 9 = 0
    JOIN #Databases d ON d.MockNo = s.MockNo AND d.DbNo = 1;

    INSERT #Blocks (BlockingId, MockNo, DayOffset, DatabaseId)
    SELECT b.Id, s.MockNo, c.DayOffset, d.DatabaseId
    FROM dbo.BlockingEvents b
    JOIN #Servers s ON s.ServerId = b.ServerId
    JOIN #Calendar c ON c.CollectedAtUtc = b.CapturedAtUtc
    JOIN #Databases d ON d.DatabaseId = b.DatabaseId
    WHERE b.SqlTextHash = CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-block-', s.MockNo)), 2);

    CREATE TABLE #LongRunning
    (
        RequestId bigint NOT NULL,
        MockNo int NOT NULL,
        DayOffset int NOT NULL,
        DatabaseId int NOT NULL
    );

    INSERT dbo.LongRunningRequestSnapshots
    (
        ServerId, DatabaseId, CapturedAtUtc, SessionId, ElapsedMs, Status, Command, WaitType, WaitTimeMs,
        CpuTimeMs, LogicalReads, Reads, Writes, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview, RequestStartTimeSource
    )
    SELECT s.ServerId, d.DatabaseId, c.CollectedAtUtc, 7000 + s.MockNo, CONVERT(bigint, 900000 + (89 - c.DayOffset) * 7500 + s.MockNo * 20000),
           N'running', N'SELECT', CASE WHEN s.MockNo % 2 = 0 THEN N'CXPACKET' ELSE N'PAGEIOLATCH_SH' END,
           30000 + s.MockNo * 1000, 85000 + (89 - c.DayOffset) * 1500, 450000 + (89 - c.DayOffset) * 4000,
           700 + s.MockNo * 20, 30 + s.MockNo, CONCAT(N'90D-DWH-', s.MockNo), N'90D Mock ETL', N'mock_etl',
           CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-long-running-', s.MockNo)), 2),
           N'SELECT COUNT_BIG(*) FROM dbo.DBA_Pulse_MockFact', DATEADD(HOUR, 3, DATEADD(MINUTE, -35, c.CollectedAtUtc))
    FROM #Servers s JOIN #Calendar c ON c.DayOffset % 7 = 0
    JOIN #Databases d ON d.MockNo = s.MockNo AND d.DbNo = 2;

    INSERT #LongRunning (RequestId, MockNo, DayOffset, DatabaseId)
    SELECT l.Id, s.MockNo, c.DayOffset, d.DatabaseId
    FROM dbo.LongRunningRequestSnapshots l
    JOIN #Servers s ON s.ServerId = l.ServerId
    JOIN #Calendar c ON c.CollectedAtUtc = l.CapturedAtUtc
    JOIN #Databases d ON d.DatabaseId = l.DatabaseId
    WHERE l.SqlTextHash = CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-long-running-', s.MockNo)), 2);

    INSERT dbo.WaitStatsSnapshots (ServerId, CapturedAtUtc, SqlServerStartTimeUtc, WaitType, WaitTimeMs, SignalWaitTimeMs, WaitingTasksCount)
    SELECT s.ServerId, c.CollectedAtUtc, DATEADD(DAY, -120, c.CollectedAtUtc), w.WaitType,
           CONVERT(bigint, 100000 + (89 - c.DayOffset) * CASE w.WaitType WHEN N'WRITELOG' THEN 2100 WHEN N'PAGEIOLATCH_SH' THEN 3600 ELSE 900 END + s.MockNo * 1000),
           CONVERT(bigint, 18000 + (89 - c.DayOffset) * CASE w.WaitType WHEN N'WRITELOG' THEN 340 WHEN N'PAGEIOLATCH_SH' THEN 520 ELSE 120 END),
           CONVERT(bigint, 90 + (89 - c.DayOffset) * CASE w.WaitType WHEN N'WRITELOG' THEN 14 WHEN N'PAGEIOLATCH_SH' THEN 22 ELSE 4 END)
    FROM #Servers s CROSS JOIN #Calendar c
    CROSS JOIN (VALUES (N'WRITELOG'),(N'PAGEIOLATCH_SH'),(N'QDS_ASYNC_QUEUE'),(N'90D_MOCK_BACKGROUND_WAIT')) w(WaitType);

    CREATE TABLE #Deadlocks
    (
        DeadlockId bigint NOT NULL,
        MockNo int NOT NULL,
        DayOffset int NOT NULL,
        DatabaseId int NOT NULL
    );

    INSERT dbo.DeadlockEvents
    (ServerId, DatabaseId, OccurredAtUtc, VictimProcessId, VictimSessionId, ProcessCount, DeadlockHash, DeadlockXml, CollectedAtUtc)
    SELECT s.ServerId, d.DatabaseId, c.CollectedAtUtc, CONCAT(N'90d-process-', s.MockNo, N'-', c.DayOffset), 8000 + s.MockNo, 2,
           CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-deadlock-', s.MockNo, N'-', c.DayOffset)), 2),
           CONVERT(xml, CONCAT(N'<deadlock><victim-list><victimProcess id="90d-process-', s.MockNo, N'-', c.DayOffset,
                              N'" /></victim-list><process-list><process id="90d-process-', s.MockNo, N'-', c.DayOffset,
                              N'" /><process id="90d-blocker-', s.MockNo, N'-', c.DayOffset, N'" /></process-list></deadlock>')),
           DATEADD(MINUTE, 2, c.CollectedAtUtc)
    FROM #Servers s JOIN #Calendar c ON c.DayOffset IN (0, 30, 60) AND s.MockNo IN (2, 5, 8)
    JOIN #Databases d ON d.MockNo = s.MockNo AND d.DbNo = 1;

    INSERT #Deadlocks (DeadlockId, MockNo, DayOffset, DatabaseId)
    SELECT d.Id, s.MockNo, c.DayOffset, db.DatabaseId
    FROM dbo.DeadlockEvents d
    JOIN #Servers s ON s.ServerId = d.ServerId
    JOIN #Calendar c ON c.CollectedAtUtc = d.OccurredAtUtc
    JOIN #Databases db ON db.DatabaseId = d.DatabaseId
    WHERE d.DeadlockHash = CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-deadlock-', s.MockNo, N'-', c.DayOffset)), 2);

    INSERT dbo.Baselines
    (
        MetricType, ServerId, DatabaseId, EntityKey, DayOfWeek, HourOfDay, WindowDays, SampleCount,
        MedianValue, P75Value, P90Value, P95Value, P99Value, MeanValue, StdDevValue, MadValue,
        MinValue, MaxValue, CalculatedAtUtc, ValidFromUtc, Status, BaselineScope
    )
    SELECT N'BlockingDuration', s.ServerId, d.DatabaseId, NULL, NULL, NULL, 30, 90,
           8500 + s.MockNo * 50, 11000 + s.MockNo * 50, 16000 + s.MockNo * 50, 22000 + s.MockNo * 50, 35000 + s.MockNo * 50,
           9500 + s.MockNo * 50, 4200, 2500, 500, 60000, @EndUtc, DATEADD(DAY, -30, @EndUtc), N'Usable', N'Global'
    FROM #Servers s JOIN #Databases d ON d.MockNo = s.MockNo
    UNION ALL
    SELECT N'BlockingFrequency', s.ServerId, d.DatabaseId, NULL, NULL, NULL, 30, 90, 1, 2, 3, 4, 6, 1.5, 1, 1, 0, 8, @EndUtc, DATEADD(DAY, -30, @EndUtc), N'Usable', N'Global'
    FROM #Servers s JOIN #Databases d ON d.MockNo = s.MockNo
    UNION ALL
    SELECT N'LongRunningDuration', s.ServerId, d.DatabaseId, CONVERT(nvarchar(256), HASHBYTES('SHA2_256', CONCAT(N'90d-long-running-', s.MockNo)), 2), NULL, NULL, 30, 90,
           900000, 1100000, 1400000, 1800000, 2600000, 980000, 250000, 120000, 300000, 3600000, @EndUtc, DATEADD(DAY, -30, @EndUtc), N'Usable', N'Global'
    FROM #Servers s JOIN #Databases d ON d.MockNo = s.MockNo AND d.DbNo = 2
    UNION ALL
    SELECT N'WaitDelta', s.ServerId, NULL, w.WaitType, NULL, NULL, 30, 90, 2000 + s.MockNo * 10, 3000, 4200, 5600, 8000, 2500, 1100, 700, 500, 12000, @EndUtc, DATEADD(DAY, -30, @EndUtc), N'Usable', N'Global'
    FROM #Servers s CROSS JOIN (VALUES (N'WRITELOG'),(N'PAGEIOLATCH_SH')) w(WaitType)
    UNION ALL
    SELECT N'JobDuration', s.ServerId, NULL, CONCAT(N'90D-', j.JobPrefix, RIGHT(CONCAT(N'0', CONVERT(varchar(2), s.MockNo)), 2)), NULL, NULL, 30, 90, 600, 780, 960, 1200, 1800, 720, 180, 90, 300, 2400, @EndUtc, DATEADD(DAY, -30, @EndUtc), N'Usable', N'Global'
    FROM #Servers s CROSS JOIN (VALUES (N'ETL-'),(N'BACKUP-'),(N'INDEX-')) j(JobPrefix)
    UNION ALL
    SELECT N'BackupDuration', s.ServerId, d.DatabaseId, b.BackupType, NULL, NULL, 30, 90,
           CASE b.BackupType WHEN N'Full' THEN 2400 WHEN N'Differential' THEN 600 ELSE 60 END,
           CASE b.BackupType WHEN N'Full' THEN 3000 WHEN N'Differential' THEN 780 ELSE 90 END,
           CASE b.BackupType WHEN N'Full' THEN 3600 WHEN N'Differential' THEN 960 ELSE 120 END,
           CASE b.BackupType WHEN N'Full' THEN 4200 WHEN N'Differential' THEN 1200 ELSE 150 END,
           CASE b.BackupType WHEN N'Full' THEN 6000 WHEN N'Differential' THEN 1800 ELSE 240 END,
           CASE b.BackupType WHEN N'Full' THEN 2600 WHEN N'Differential' THEN 650 ELSE 65 END,
           350, 180, 30, CASE b.BackupType WHEN N'Full' THEN 7200 WHEN N'Differential' THEN 1800 ELSE 600 END,
           @EndUtc, DATEADD(DAY, -30, @EndUtc), N'Usable', N'Global'
    FROM #Servers s JOIN #Databases d ON d.MockNo = s.MockNo CROSS JOIN (VALUES (N'Full'),(N'Differential'),(N'Log')) b(BackupType)
    WHERE b.BackupType <> N'Log' OR d.RecoveryModel <> N'SIMPLE'
    UNION ALL
    SELECT N'DatabaseGrowth', s.ServerId, d.DatabaseId, NULL, NULL, NULL, 30, 90, 1200, 1600, 2200, 3000, 4800, 1400, 650, 400, 0, 9000, @EndUtc, DATEADD(DAY, -30, @EndUtc), N'Usable', N'Global'
    FROM #Servers s JOIN #Databases d ON d.MockNo = s.MockNo;

    CREATE TABLE #Anomalies
    (
        AnomalyId bigint NOT NULL,
        MockNo int NOT NULL,
        DatabaseId int NULL,
        MetricType nvarchar(64) NOT NULL
    );

    INSERT dbo.AnomalyFindings
    (
        MetricType, ServerId, DatabaseId, EntityKey, ObservedAtUtc, ObservedValue, BaselineMedian, BaselineP95, BaselineP99,
        BaselineMad, DeviationRatio, ModifiedZScore, BaselineScope, SampleCount, Severity, Status, ExplanationCode,
        Fingerprint, StartedAtUtc, LastSeenAtUtc, ObservationCount, NormalSampleCount, SourceEntityId, CreatedAtUtc, UpdatedAtUtc
    )
    SELECT N'BlockingDuration', s.ServerId, b.DatabaseId, NULL, c.CollectedAtUtc, 65000 + s.MockNo * 500, 8500 + s.MockNo * 50,
           22000 + s.MockNo * 50, 35000 + s.MockNo * 50, 2500, 7.65, 22.10, N'Global', 90, N'Critical', N'Active', N'ABOVE_P99',
           CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-anomaly-blocking-', s.MockNo)), 2), c.CollectedAtUtc, c.CollectedAtUtc, 1, 0, b.BlockingId, @EndUtc, @EndUtc
    FROM #Blocks b JOIN #Servers s ON s.MockNo = b.MockNo JOIN #Calendar c ON c.DayOffset = b.DayOffset
    WHERE b.DayOffset = 0 AND b.MockNo IN (3, 6, 9);

    INSERT dbo.AnomalyFindings
    (
        MetricType, ServerId, DatabaseId, EntityKey, ObservedAtUtc, ObservedValue, BaselineMedian, BaselineP95, BaselineP99,
        BaselineMad, DeviationRatio, ModifiedZScore, BaselineScope, SampleCount, Severity, Status, ExplanationCode,
        Fingerprint, StartedAtUtc, LastSeenAtUtc, ObservationCount, NormalSampleCount, SourceEntityId, CreatedAtUtc, UpdatedAtUtc
    )
    SELECT N'DatabaseGrowth', s.ServerId, d.DatabaseId, NULL, c.CollectedAtUtc, 18000 + s.MockNo * 100, 1200, 3000, 4800,
           400, 15.0, 28.4, N'Global', 90, N'Warning', N'Active', N'GROWTH_SPIKE',
           CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-anomaly-growth-', s.MockNo)), 2), c.CollectedAtUtc, c.CollectedAtUtc, 1, 0, NULL, @EndUtc, @EndUtc
    FROM #Servers s JOIN #Databases d ON d.MockNo = s.MockNo AND d.DbNo = 3 CROSS JOIN (SELECT CollectedAtUtc FROM #Calendar WHERE DayOffset = 0) c
    WHERE s.MockNo IN (4, 8);

    INSERT #Anomalies (AnomalyId, MockNo, DatabaseId, MetricType)
    SELECT a.Id, s.MockNo, a.DatabaseId, a.MetricType
    FROM dbo.AnomalyFindings a
    JOIN #Servers s ON s.ServerId = a.ServerId
    WHERE a.Fingerprint = CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-anomaly-', a.MetricType, N'-', s.MockNo)), 2)
       OR a.Fingerprint = CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-anomaly-blocking-', s.MockNo)), 2)
       OR a.Fingerprint = CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-anomaly-growth-', s.MockNo)), 2);

    CREATE TABLE #Ops
    (
        EventId bigint NOT NULL,
        MockNo int NOT NULL,
        DatabaseId int NULL,
        EventType nvarchar(40) NOT NULL
    );

    INSERT dbo.OperationalEvents
    (EventType, ServerId, DatabaseId, Fingerprint, StartedAtUtc, LastSeenAtUtc, EndedAtUtc, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary, SourceEntityId, CreatedAtUtc, UpdatedAtUtc, AdditionalData)
    SELECT N'Blocking', s.ServerId, b.DatabaseId, CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-op-blocking-', s.MockNo)), 2),
           c.CollectedAtUtc, c.CollectedAtUtc, NULL, 65000 + s.MockNo * 500, N'Active', N'Critical', 1, 1,
           CONCAT(N'90-day mock blocking on ', d.DatabaseName), CONCAT(N'Session ', 6000 + s.MockNo, N' blocked session ', 5000 + s.MockNo, N'.'), b.BlockingId, @EndUtc, @EndUtc, @SeedMarker
    FROM #Blocks b JOIN #Servers s ON s.MockNo = b.MockNo JOIN #Databases d ON d.DatabaseId = b.DatabaseId CROSS JOIN (SELECT CollectedAtUtc FROM #Calendar WHERE DayOffset = 0) c
    WHERE b.DayOffset = 0 AND b.MockNo IN (3, 6, 9);

    INSERT dbo.OperationalEvents
    (EventType, ServerId, DatabaseId, Fingerprint, StartedAtUtc, LastSeenAtUtc, EndedAtUtc, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary, SourceEntityId, CreatedAtUtc, UpdatedAtUtc, AdditionalData)
    SELECT N'LongRunning', s.ServerId, l.DatabaseId, CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-op-long-running-', s.MockNo)), 2),
           c.CollectedAtUtc, c.CollectedAtUtc, NULL, 1800000 + s.MockNo * 10000, N'Active', N'Warning', 1, 1,
           CONCAT(N'90-day mock long-running request on ', d.DatabaseName), N'Mock request remains above the long-running threshold.', l.RequestId, @EndUtc, @EndUtc, @SeedMarker
    FROM #LongRunning l JOIN #Servers s ON s.MockNo = l.MockNo JOIN #Databases d ON d.DatabaseId = l.DatabaseId CROSS JOIN (SELECT CollectedAtUtc FROM #Calendar WHERE DayOffset = 0) c
    WHERE l.DayOffset = 0 AND l.MockNo IN (2, 4, 6, 8, 10);

    INSERT dbo.OperationalEvents
    (EventType, ServerId, DatabaseId, Fingerprint, StartedAtUtc, LastSeenAtUtc, EndedAtUtc, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary, SourceEntityId, CreatedAtUtc, UpdatedAtUtc, AdditionalData)
    SELECT N'Deadlock', s.ServerId, dl.DatabaseId, CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-op-deadlock-', s.MockNo)), 2),
           c.CollectedAtUtc, c.CollectedAtUtc, c.CollectedAtUtc, 0, N'Resolved', N'Warning', 1, 2,
           CONCAT(N'90-day mock deadlock on ', d.DatabaseName), N'Mock deadlock event with two processes.', dl.DeadlockId, @EndUtc, @EndUtc, @SeedMarker
    FROM #Deadlocks dl JOIN #Servers s ON s.MockNo = dl.MockNo JOIN #Databases d ON d.DatabaseId = dl.DatabaseId CROSS JOIN (SELECT CollectedAtUtc FROM #Calendar WHERE DayOffset = 0) c
    WHERE dl.DayOffset = 0;

    ;WITH EventSeed AS
    (
        SELECT 5 MockNo, 1 DbNo, N'BackupProtection' EventType, N'Warning' Severity, N'Backup protection age exceeds mock policy.' Summary, N'Active' Status
        UNION ALL SELECT 3, 1, N'AlwaysOnHealth', N'Critical', N'Mock secondary replica is not synchronizing.', N'Active'
        UNION ALL SELECT 7, NULL, N'JobFailure', N'Critical', N'Mock ETL validation execution failed.', N'Resolved'
        UNION ALL SELECT 9, 2, N'CapacityRisk', N'Warning', N'Mock database growth is approaching volume capacity.', N'Active'
    )
    INSERT dbo.OperationalEvents
    (EventType, ServerId, DatabaseId, Fingerprint, StartedAtUtc, LastSeenAtUtc, EndedAtUtc, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary, SourceEntityId, CreatedAtUtc, UpdatedAtUtc, AdditionalData)
    SELECT e.EventType, s.ServerId, d.DatabaseId, CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-op-', e.EventType, N'-', e.MockNo)), 2),
           DATEADD(HOUR, CASE WHEN e.Status = N'Resolved' THEN -6 ELSE -2 END, c.CollectedAtUtc), c.CollectedAtUtc,
           CASE WHEN e.Status = N'Resolved' THEN c.CollectedAtUtc ELSE NULL END,
           CASE WHEN e.Status = N'Resolved' THEN 0 ELSE 7200000 END, e.Status, e.Severity, 1, NULL,
           CONCAT(N'90-day mock ', e.EventType, N' on ', COALESCE(d.DatabaseName, s.ServerName)), e.Summary, NULL, @EndUtc, @EndUtc, @SeedMarker
    FROM EventSeed e JOIN #Servers s ON s.MockNo = e.MockNo
    LEFT JOIN #Databases d ON d.MockNo = e.MockNo AND d.DbNo = e.DbNo
    CROSS JOIN (SELECT CollectedAtUtc FROM #Calendar WHERE DayOffset = 0) c;

    INSERT dbo.OperationalEvents
    (EventType, ServerId, DatabaseId, Fingerprint, StartedAtUtc, LastSeenAtUtc, EndedAtUtc, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary, SourceEntityId, CreatedAtUtc, UpdatedAtUtc, AdditionalData)
    SELECT CASE WHEN a.MetricType = N'DatabaseGrowth' THEN N'GrowthAnomaly' ELSE N'PerformanceAnomaly' END,
           s.ServerId, a.DatabaseId, CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-op-anomaly-', a.MetricType, N'-', s.MockNo)), 2),
           c.CollectedAtUtc, c.CollectedAtUtc, NULL, 0, N'Active', CASE WHEN a.MetricType = N'DatabaseGrowth' THEN N'Warning' ELSE N'Critical' END,
           1, NULL, CONCAT(N'90-day mock ', a.MetricType, N' anomaly'), N'Mock anomaly finding generated for dashboard validation.', a.AnomalyId, @EndUtc, @EndUtc, @SeedMarker
    FROM #Anomalies a JOIN #Servers s ON s.MockNo = a.MockNo CROSS JOIN (SELECT CollectedAtUtc FROM #Calendar WHERE DayOffset = 0) c;

    INSERT #Ops (EventId, MockNo, DatabaseId, EventType)
    SELECT e.Id, s.MockNo, e.DatabaseId, e.EventType
    FROM dbo.OperationalEvents e
    JOIN #Servers s ON s.ServerId = e.ServerId
    WHERE e.AdditionalData = @SeedMarker AND e.CreatedAtUtc = @EndUtc;

    CREATE TABLE #Groups
    (
        GroupId bigint NOT NULL,
        MockNo int NOT NULL,
        DatabaseId int NULL
    );

    INSERT dbo.ManagementCorrelationGroups
    (GroupFingerprint, ServerId, DatabaseId, WindowStartUtc, WindowEndUtc, LastSeenAtUtc, SignalCount, Status, CreatedAtUtc, UpdatedAtUtc)
    SELECT CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-group-', o.MockNo)), 2), s.ServerId, o.DatabaseId,
           DATEADD(MINUTE, -15, c.CollectedAtUtc), c.CollectedAtUtc, c.CollectedAtUtc, COUNT(*), N'Active', @EndUtc, @EndUtc
    FROM #Ops o JOIN #Servers s ON s.MockNo = o.MockNo CROSS JOIN (SELECT CollectedAtUtc FROM #Calendar WHERE DayOffset = 0) c
    WHERE o.EventType IN (N'Blocking', N'PerformanceAnomaly', N'GrowthAnomaly')
    GROUP BY o.MockNo, s.ServerId, o.DatabaseId, c.CollectedAtUtc;

    INSERT #Groups (GroupId, MockNo, DatabaseId)
    SELECT g.Id, s.MockNo, g.DatabaseId
    FROM dbo.ManagementCorrelationGroups g
    JOIN #Servers s ON s.ServerId = g.ServerId
    WHERE g.GroupFingerprint = CONVERT(varchar(64), HASHBYTES('SHA2_256', CONCAT(N'90d-group-', s.MockNo)), 2);

    INSERT dbo.ManagementRelatedSignals
    (CorrelationGroupId, SignalType, Domain, SignalId, ServerId, DatabaseId, Severity, Status, StartedAtUtc, LastSeenAtUtc, Title, SourceType, CorrelationStrength, TimeDifferenceSeconds, CreatedAtUtc)
    SELECT g.GroupId, N'OperationalEvent', CASE WHEN o.EventType IN (N'Blocking', N'PerformanceAnomaly') THEN N'Performance' ELSE N'Capacity' END,
           o.EventId, s.ServerId, o.DatabaseId, CASE WHEN o.EventType = N'GrowthAnomaly' THEN N'Warning' ELSE N'Critical' END,
           N'Active', DATEADD(MINUTE, -5, c.CollectedAtUtc), c.CollectedAtUtc, CONCAT(N'90-day mock ', o.EventType), N'OperationalEvents', N'Strong', 0, @EndUtc
    FROM #Groups g JOIN #Ops o ON o.MockNo = g.MockNo AND (o.DatabaseId = g.DatabaseId OR (o.DatabaseId IS NULL AND g.DatabaseId IS NULL))
    JOIN #Servers s ON s.MockNo = o.MockNo CROSS JOIN (SELECT CollectedAtUtc FROM #Calendar WHERE DayOffset = 0) c
    WHERE o.EventType IN (N'Blocking', N'PerformanceAnomaly', N'GrowthAnomaly');

    INSERT dbo.AuditLogs
    (OccurredAtUtc, UserName, UserRole, Action, ResourceType, ResourceId, HttpMethod, RequestPath, Result, StatusCode, DurationMs, CorrelationId, ClientIp, UserAgent, AdditionalData)
    SELECT c.CollectedAtUtc, N'mock.operator', N'Unauthenticated',
           CASE (s.MockNo + c.DayOffset) % 4 WHEN 0 THEN N'Dashboard.View' WHEN 1 THEN N'Performance.View' WHEN 2 THEN N'Capacity.View' ELSE N'Operations.EventList.View' END,
           N'MockTelemetry', CONVERT(nvarchar(128), s.ServerId), N'GET',
           CASE (s.MockNo + c.DayOffset) % 4 WHEN 0 THEN N'/api/dashboard' WHEN 1 THEN N'/api/performance/overview' WHEN 2 THEN N'/api/capacity/databases' ELSE N'/api/operations/events' END,
           CASE WHEN s.MockNo = 4 AND c.DayOffset IN (27, 63) THEN N'Failed' ELSE N'Success' END,
           CASE WHEN s.MockNo = 4 AND c.DayOffset IN (27, 63) THEN 500 ELSE 200 END,
           12 + s.MockNo * 3, CONCAT(N'90d-mock-', s.MockNo, N'-', c.DayOffset), N'127.0.0.1', N'DBA Pulse 90-day mock seed',
           CONCAT(N'{"seed":"', @SeedMarker, N'","server":', s.MockNo, N'}')
    FROM #Servers s CROSS JOIN #Calendar c;

    COMMIT TRANSACTION;
    PRINT N'DBA Pulse 90-day mock seed inserted: 10 servers, 30 databases, 90 daily collection points.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
