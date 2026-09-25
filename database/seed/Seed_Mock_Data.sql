/*
   DBA Pulse lab-only mock data.

   This is intentionally NOT a migration and must not be copied into
   database/migrations. It creates an isolated mock server/database context
   and leaves existing lab telemetry untouched. Re-running the script is a
   no-op when the mock server already exists.
*/
USE DBA_PULSE;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = N'DBAPULSE-MOCK-SQL01')
BEGIN
    PRINT N'DBAPULSE mock data already exists; no rows inserted.';
    RETURN;
END;

BEGIN TRANSACTION;

DECLARE @SeedAtUtc datetime2(3) = DATEADD(MINUTE, -10, SYSUTCDATETIME());
DECLARE @ServerId int;
DECLARE @DatabaseId int;
DECLARE @DatabaseId2 int;
DECLARE @RunId bigint;
DECLARE @ErrorRunId bigint;
DECLARE @BlockingId bigint;
DECLARE @JobId bigint;
DECLARE @DeadlockId bigint;
DECLARE @EventId bigint;
DECLARE @GroupId bigint;

INSERT dbo.Servers (ServerName, InstanceName, SqlVersion, Edition, TimeZoneId, LastSeenAtUtc, IsActive)
VALUES (N'DBAPULSE-MOCK-SQL01', N'DBAPULSE-MOCK-SQL01', N'SQL Server 2022 (Mock)', N'Developer (Mock)', N'Europe/Istanbul', @SeedAtUtc, 1);
SET @ServerId = CONVERT(int, SCOPE_IDENTITY());

INSERT dbo.Databases (ServerId, DatabaseName, RecoveryModel, DatabaseStatus, LastSeenAtUtc, IsActive)
VALUES (@ServerId, N'DBAPULSE_MOCK_CORE', N'FULL', N'ONLINE', @SeedAtUtc, 1);
SET @DatabaseId = CONVERT(int, SCOPE_IDENTITY());

INSERT dbo.Databases (ServerId, DatabaseName, RecoveryModel, DatabaseStatus, LastSeenAtUtc, IsActive)
VALUES (@ServerId, N'DBAPULSE_MOCK_DWH', N'SIMPLE', N'ONLINE', @SeedAtUtc, 1);
SET @DatabaseId2 = CONVERT(int, SCOPE_IDENTITY());

INSERT dbo.CollectionRuns (StartedAtUtc, FinishedAtUtc, Status, DurationMs)
VALUES (@SeedAtUtc, DATEADD(SECOND, 18, @SeedAtUtc), N'Success', 18000);
SET @RunId = CONVERT(bigint, SCOPE_IDENTITY());

INSERT dbo.CollectionRuns (StartedAtUtc, FinishedAtUtc, Status, DurationMs)
VALUES (DATEADD(SECOND, 30, @SeedAtUtc), DATEADD(SECOND, 35, @SeedAtUtc), N'PartialSuccess', 5000);
SET @ErrorRunId = CONVERT(bigint, SCOPE_IDENTITY());

INSERT dbo.CollectionErrors (CollectionRunId, QueryName, ServerName, ErrorMessage, CreatedAtUtc)
VALUES (@ErrorRunId, N'mock/performance.sql', N'DBAPULSE-MOCK-SQL01', N'Mock collection failure for UI and failure-semantics validation.', DATEADD(SECOND, 35, @SeedAtUtc));

INSERT dbo.ServerSnapshots (CollectionRunId, ServerId, CollectedAtUtc, UptimeSeconds)
VALUES (@RunId, @ServerId, @SeedAtUtc, 864000);

INSERT dbo.DatabaseSnapshots (CollectionRunId, DatabaseId, CollectedAtUtc, DatabaseStatus, UserAccess, CompatibilityLevel, IsReadOnly, IsEncrypted)
VALUES (@RunId, @DatabaseId, @SeedAtUtc, N'ONLINE', N'MULTI_USER', 160, 0, 1),
       (@RunId, @DatabaseId2, @SeedAtUtc, N'ONLINE', N'MULTI_USER', 160, 0, 0);

INSERT dbo.BackupSnapshots (CollectionRunId, ServerId, DatabaseId, DatabaseName, CollectedAtUtc, BackupType, BackupStartAtSource, BackupFinishAtSource, BackupSizeMb, CompressedBackupSizeMb, IsCopyOnly, BackupDurationSeconds)
VALUES (@RunId, @ServerId, @DatabaseId, N'DBAPULSE_MOCK_CORE', DATEADD(MINUTE, -20, @SeedAtUtc), N'Full', DATEADD(MINUTE, -70, @SeedAtUtc), DATEADD(MINUTE, -20, @SeedAtUtc), 512000, 204800, 0, 3000),
       (@RunId, @ServerId, @DatabaseId, N'DBAPULSE_MOCK_CORE', DATEADD(MINUTE, -8, @SeedAtUtc), N'Log', DATEADD(MINUTE, -9, @SeedAtUtc), DATEADD(MINUTE, -8, @SeedAtUtc), 1280, 640, 0, 60),
       (@RunId, @ServerId, @DatabaseId, N'DBAPULSE_MOCK_CORE', DATEADD(HOUR, -6, @SeedAtUtc), N'Differential', DATEADD(HOUR, -6, @SeedAtUtc), DATEADD(MINUTE, -355, @SeedAtUtc), 25600, 10240, 0, 5),
       (@RunId, @ServerId, @DatabaseId2, N'DBAPULSE_MOCK_DWH', DATEADD(HOUR, -4, @SeedAtUtc), N'Full', DATEADD(HOUR, -5, @SeedAtUtc), DATEADD(HOUR, -4, @SeedAtUtc), 768000, 307200, 1, 3600),
       (@RunId, @ServerId, @DatabaseId2, N'DBAPULSE_MOCK_DWH', DATEADD(HOUR, -2, @SeedAtUtc), N'Differential', DATEADD(HOUR, -2, @SeedAtUtc), DATEADD(MINUTE, -115, @SeedAtUtc), 38400, 15360, 0, 5),
       (@RunId, @ServerId, @DatabaseId2, N'DBAPULSE_MOCK_DWH', DATEADD(MINUTE, -30, @SeedAtUtc), N'Log', DATEADD(MINUTE, -31, @SeedAtUtc), DATEADD(MINUTE, -30, @SeedAtUtc), 2048, 1024, 0, 60);

INSERT dbo.JobSnapshots (CollectionRunId, ServerId, CollectedAtUtc, JobId, JobName, Enabled, LastRunStatus, LastRunAtSource, LastRunDurationSeconds, LastRunMessage, IsRunning, CurrentStartAtSource, CurrentDurationSeconds, NextRunAtSource, FailureCount24Hours, FailureCount7Days, RepeatedFailure, AverageDurationSeconds, MaxDurationSeconds)
VALUES (@RunId, @ServerId, @SeedAtUtc, N'MOCK-JOB-FAILED', N'Mock Nightly ETL', 1, N'Failed', DATEADD(MINUTE, -35, @SeedAtUtc), 1860, N'Mock failure: validation step returned non-zero.', 0, NULL, NULL, DATEADD(HOUR, 23, @SeedAtUtc), 2, 5, 1, 540, 780),
       (@RunId, @ServerId, @SeedAtUtc, N'MOCK-JOB-RUNNING', N'Mock Index Maintenance', 1, N'Running', DATEADD(MINUTE, -25, @SeedAtUtc), NULL, NULL, 1, DATEADD(MINUTE, -25, @SeedAtUtc), 1500, DATEADD(HOUR, 6, @SeedAtUtc), 0, 0, 0, 900, 1200);

INSERT dbo.AlwaysOnSnapshots (CollectionRunId, ServerId, CollectedAtUtc, AvailabilityGroupName, ReplicaServerName, RoleDescription, OperationalState, ConnectedState, SynchronizationHealth, DatabaseName, SynchronizationState, DatabaseState, IsSuspended, SuspendReason, LogSendQueueMb, RedoQueueMb, LogSendRateMb, RedoRateMb, LastCommitTimeSource)
VALUES (@RunId, @ServerId, @SeedAtUtc, N'MockCoreAG', N'DBAPULSE-MOCK-SQL01', N'PRIMARY', N'ONLINE', N'CONNECTED', N'HEALTHY', N'DBAPULSE_MOCK_CORE', N'SYNCHRONIZED', N'ONLINE', 0, NULL, 0, 0, 85, 90, @SeedAtUtc),
       (@RunId, @ServerId, @SeedAtUtc, N'MockCoreAG', N'DBAPULSE-MOCK-SQL02', N'SECONDARY', N'ONLINE', N'CONNECTED', N'NOT_HEALTHY', N'DBAPULSE_MOCK_CORE', N'NOT_SYNCHRONIZING', N'ONLINE', 0, NULL, 18432, 9216, 40, 12, DATEADD(MINUTE, -8, @SeedAtUtc));

;WITH N(n) AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7)) v(n))
INSERT dbo.CapacitySnapshots (CollectionRunId, ServerId, DatabaseId, DatabaseName, CollectedAtUtc, FileType, AllocatedSizeMb, FileCount)
SELECT @RunId, @ServerId, d.DatabaseId, d.DatabaseName, DATEADD(DAY, -n.n, @SeedAtUtc), f.FileType,
       CASE WHEN d.DatabaseId = @DatabaseId AND f.FileType = N'Data' THEN 102400 - n.n * 2048
            WHEN d.DatabaseId = @DatabaseId AND f.FileType = N'Log' THEN 20480 - n.n * 512
            WHEN d.DatabaseId = @DatabaseId2 AND f.FileType = N'Data' THEN 512000 - n.n * 8192
            ELSE 51200 - n.n * 1024 END,
       1
FROM N n CROSS JOIN (VALUES (@DatabaseId, N'DBAPULSE_MOCK_CORE'), (@DatabaseId2, N'DBAPULSE_MOCK_DWH')) d(DatabaseId, DatabaseName)
CROSS JOIN (VALUES (N'Data'), (N'Log')) f(FileType);

;WITH N(n) AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7)) v(n))
INSERT dbo.VolumeCapacitySnapshots (CollectionRunId, ServerId, VolumeId, CollectedAtUtc, TotalBytes, AvailableBytes)
SELECT @RunId, @ServerId, N'DBAPULSE-MOCK-VOLUME-D', DATEADD(DAY, -n.n, @SeedAtUtc), 2199023255552, 375809638400 + n.n * 5368709120
FROM N n;

INSERT dbo.BlockingEvents (ServerId, DatabaseId, CapturedAtUtc, SessionId, BlockingSessionId, WaitType, WaitDurationMs, Command, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview)
VALUES (@ServerId, @DatabaseId, DATEADD(MINUTE, -8, @SeedAtUtc), 155, 162, N'LCK_M_X', 4200, N'UPDATE', N'MOCK-APP-01', N'Mock API', N'mock_user', REPLICATE('a', 64), N'UPDATE dbo.MockWorkload SET Value = Value + 1 WHERE Id = 1'),
       (@ServerId, @DatabaseId, DATEADD(MINUTE, -5, @SeedAtUtc), 155, 162, N'LCK_M_X', 17200, N'UPDATE', N'MOCK-APP-01', N'Mock API', N'mock_user', REPLICATE('a', 64), N'UPDATE dbo.MockWorkload SET Value = Value + 1 WHERE Id = 1'),
       (@ServerId, @DatabaseId, DATEADD(MINUTE, -2, @SeedAtUtc), 155, 162, N'LCK_M_X', 38000, N'UPDATE', N'MOCK-APP-01', N'Mock API', N'mock_user', REPLICATE('a', 64), N'UPDATE dbo.MockWorkload SET Value = Value + 1 WHERE Id = 1');
SELECT TOP (1) @BlockingId = Id FROM dbo.BlockingEvents WHERE ServerId = @ServerId ORDER BY Id DESC;

INSERT dbo.LongRunningRequestSnapshots (ServerId, DatabaseId, CapturedAtUtc, SessionId, ElapsedMs, Status, Command, WaitType, WaitTimeMs, CpuTimeMs, LogicalReads, Reads, Writes, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview, RequestStartTimeSource)
VALUES (@ServerId, @DatabaseId2, DATEADD(MINUTE, -8, @SeedAtUtc), 275, 1980000, N'running', N'SELECT', N'CXPACKET', 45000, 120000, 880000, 1200, 40, N'MOCK-DWH-01', N'Mock ETL', N'mock_etl', REPLICATE('b', 64), N'SELECT COUNT_BIG(*) FROM dbo.MockFact', DATEADD(MINUTE, -33, @SeedAtUtc)),
       (@ServerId, @DatabaseId2, DATEADD(MINUTE, -5, @SeedAtUtc), 275, 1800000, N'running', N'SELECT', N'CXPACKET', 40000, 108000, 760000, 1000, 35, N'MOCK-DWH-01', N'Mock ETL', N'mock_etl', REPLICATE('b', 64), N'SELECT COUNT_BIG(*) FROM dbo.MockFact', DATEADD(MINUTE, -30, @SeedAtUtc)),
       (@ServerId, @DatabaseId2, DATEADD(MINUTE, -2, @SeedAtUtc), 275, 1620000, N'running', N'SELECT', N'CXPACKET', 35000, 96000, 650000, 900, 30, N'MOCK-DWH-01', N'Mock ETL', N'mock_etl', REPLICATE('b', 64), N'SELECT COUNT_BIG(*) FROM dbo.MockFact', DATEADD(MINUTE, -27, @SeedAtUtc));

;WITH N(n) AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7)) v(n))
INSERT dbo.WaitStatsSnapshots (ServerId, CapturedAtUtc, SqlServerStartTimeUtc, WaitType, WaitTimeMs, SignalWaitTimeMs, WaitingTasksCount)
SELECT @ServerId, DATEADD(DAY, -n.n, @SeedAtUtc), DATEADD(DAY, -30, @SeedAtUtc), w.WaitType,
       CASE w.WaitType WHEN N'WRITELOG' THEN 120000 + (7-n.n)*5000 WHEN N'PAGEIOLATCH_SH' THEN 350000 + (7-n.n)*12000 ELSE 90000 + (7-n.n)*1000 END,
       CASE w.WaitType WHEN N'WRITELOG' THEN 22000 + (7-n.n)*800 WHEN N'PAGEIOLATCH_SH' THEN 45000 + (7-n.n)*1200 ELSE 12000 + (7-n.n)*300 END,
       CASE w.WaitType WHEN N'WRITELOG' THEN 400 + (7-n.n)*15 WHEN N'PAGEIOLATCH_SH' THEN 900 + (7-n.n)*25 ELSE 100 + (7-n.n)*5 END
FROM N n CROSS JOIN (VALUES (N'WRITELOG'), (N'PAGEIOLATCH_SH'), (N'QDS_ASYNC_QUEUE')) w(WaitType);

INSERT dbo.DeadlockEvents (ServerId, DatabaseId, OccurredAtUtc, VictimProcessId, VictimSessionId, ProcessCount, DeadlockHash, DeadlockXml, CollectedAtUtc)
VALUES (@ServerId, @DatabaseId, DATEADD(MINUTE, -12, @SeedAtUtc), N'process_mock_1', 188, 2, REPLICATE('c', 64), N'<deadlock><victim-list><victimProcess id="process_mock_1" /></victim-list><process-list><process id="process_mock_1" /><process id="process_mock_2" /></process-list></deadlock>', @SeedAtUtc);
SELECT TOP (1) @DeadlockId = Id FROM dbo.DeadlockEvents WHERE ServerId = @ServerId ORDER BY Id DESC;

INSERT dbo.Baselines (MetricType, ServerId, DatabaseId, EntityKey, DayOfWeek, HourOfDay, WindowDays, SampleCount, MedianValue, P75Value, P90Value, P95Value, P99Value, MeanValue, StdDevValue, MadValue, MinValue, MaxValue, CalculatedAtUtc, ValidFromUtc, Status, BaselineScope)
VALUES (N'BlockingDuration', @ServerId, @DatabaseId, NULL, NULL, NULL, 30, 30, 4500, 7000, 9000, 11000, 15000, 5200, 2400, 1200, 500, 15000, @SeedAtUtc, DATEADD(DAY, -30, @SeedAtUtc), N'Usable', N'Global'),
       (N'BlockingFrequency', @ServerId, @DatabaseId, NULL, NULL, NULL, 30, 30, 1, 2, 3, 4, 6, 1.4, 1.1, 1, 0, 8, @SeedAtUtc, DATEADD(DAY, -30, @SeedAtUtc), N'Usable', N'Global'),
       (N'LongRunningDuration', @ServerId, @DatabaseId2, REPLICATE('b', 64), NULL, NULL, 30, 30, 600000, 750000, 900000, 1200000, 1800000, 680000, 250000, 120000, 300000, 1800000, @SeedAtUtc, DATEADD(DAY, -30, @SeedAtUtc), N'Usable', N'Global'),
       (N'WaitDelta', @ServerId, NULL, N'WRITELOG', NULL, NULL, 30, 30, 2500, 4000, 6000, 8000, 12000, 3100, 1800, 900, 500, 12000, @SeedAtUtc, DATEADD(DAY, -30, @SeedAtUtc), N'Usable', N'Global'),
       (N'JobDuration', @ServerId, NULL, N'MOCK-JOB-FAILED', NULL, NULL, 30, 30, 540, 600, 660, 780, 900, 560, 100, 60, 420, 900, @SeedAtUtc, DATEADD(DAY, -30, @SeedAtUtc), N'Usable', N'Global'),
       (N'BackupDuration', @ServerId, @DatabaseId, N'Full', NULL, NULL, 30, 30, 900, 1200, 1500, 1800, 2400, 980, 300, 180, 600, 2400, @SeedAtUtc, DATEADD(DAY, -30, @SeedAtUtc), N'Usable', N'Global'),
       (N'DatabaseGrowth', @ServerId, @DatabaseId2, NULL, NULL, NULL, 30, 30, 2048, 3072, 4096, 5120, 8192, 2300, 1300, 800, 512, 8192, @SeedAtUtc, DATEADD(DAY, -30, @SeedAtUtc), N'Usable', N'Global');

INSERT dbo.AnomalyFindings (MetricType, ServerId, DatabaseId, EntityKey, ObservedAtUtc, ObservedValue, BaselineMedian, BaselineP95, BaselineP99, BaselineMad, DeviationRatio, ModifiedZScore, BaselineScope, SampleCount, Severity, Status, ExplanationCode, Fingerprint, StartedAtUtc, LastSeenAtUtc, ObservationCount, NormalSampleCount, SourceEntityId, CreatedAtUtc, UpdatedAtUtc)
VALUES (N'BlockingDuration', @ServerId, @DatabaseId, NULL, DATEADD(MINUTE, -2, @SeedAtUtc), 38000, 4500, 11000, 15000, 1200, 8.444444, 18.843750, N'Global', 30, N'Critical', N'Active', N'ABOVE_P99', REPLICATE('d', 64), DATEADD(MINUTE, -8, @SeedAtUtc), DATEADD(MINUTE, -2, @SeedAtUtc), 3, 0, @BlockingId, @SeedAtUtc, @SeedAtUtc),
       (N'LongRunningDuration', @ServerId, @DatabaseId2, REPLICATE('b', 64), DATEADD(MINUTE, -2, @SeedAtUtc), 1620000, 600000, 1200000, 1800000, 120000, 2.700000, 5.737500, N'Global', 30, N'Warning', N'Active', N'ABOVE_P95', REPLICATE('e', 64), DATEADD(MINUTE, -8, @SeedAtUtc), DATEADD(MINUTE, -2, @SeedAtUtc), 3, 0, NULL, @SeedAtUtc, @SeedAtUtc),
       (N'DatabaseGrowth', @ServerId, @DatabaseId2, NULL, @SeedAtUtc, 18432, 2048, 5120, 8192, 800, 9.000000, 13.802500, N'Global', 30, N'Critical', N'Active', N'GROWTH_SPIKE', REPLICATE('f', 64), DATEADD(DAY, -1, @SeedAtUtc), @SeedAtUtc, 2, 0, NULL, @SeedAtUtc, @SeedAtUtc);

INSERT dbo.OperationalEvents (EventType, ServerId, DatabaseId, Fingerprint, StartedAtUtc, LastSeenAtUtc, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary, SourceEntityId, CreatedAtUtc, UpdatedAtUtc, AdditionalData)
VALUES (N'Blocking', @ServerId, @DatabaseId, REPLICATE('1', 64), DATEADD(MINUTE, -8, @SeedAtUtc), DATEADD(MINUTE, -2, @SeedAtUtc), 360000, N'Active', N'Critical', 3, 1, N'Mock blocking on DBAPULSE_MOCK_CORE', N'Session 162 blocked session 155 for 38 seconds. Mock telemetry.', @BlockingId, @SeedAtUtc, @SeedAtUtc, N'{"seed":"DBAPULSE_PHASE8_MOCK"}'),
       (N'LongRunning', @ServerId, @DatabaseId2, REPLICATE('2', 64), DATEADD(MINUTE, -8, @SeedAtUtc), DATEADD(MINUTE, -2, @SeedAtUtc), 360000, N'Active', N'Warning', 3, 1, N'Mock long-running request on DBAPULSE_MOCK_DWH', N'Mock request has been running for 27 minutes.', NULL, @SeedAtUtc, @SeedAtUtc, N'{"seed":"DBAPULSE_PHASE8_MOCK"}'),
       (N'Deadlock', @ServerId, @DatabaseId, REPLICATE('3', 64), DATEADD(MINUTE, -12, @SeedAtUtc), DATEADD(MINUTE, -12, @SeedAtUtc), 0, N'Resolved', N'Warning', 1, 2, N'Mock deadlock on DBAPULSE_MOCK_CORE', N'Mock deadlock event with two processes.', @DeadlockId, @SeedAtUtc, @SeedAtUtc, N'{"seed":"DBAPULSE_PHASE8_MOCK"}'),
       (N'BackupProtection', @ServerId, @DatabaseId, REPLICATE('4', 64), DATEADD(HOUR, -2, @SeedAtUtc), @SeedAtUtc, 7200000, N'Active', N'Warning', 1, NULL, N'Mock backup protection warning', N'Mock backup age exceeds the lab policy threshold.', NULL, @SeedAtUtc, @SeedAtUtc, N'{"seed":"DBAPULSE_PHASE8_MOCK"}'),
       (N'AlwaysOnHealth', @ServerId, @DatabaseId, REPLICATE('5', 64), DATEADD(MINUTE, -10, @SeedAtUtc), @SeedAtUtc, 600000, N'Active', N'Critical', 1, NULL, N'Mock Always On health warning', N'Mock secondary replica is not synchronizing.', NULL, @SeedAtUtc, @SeedAtUtc, N'{"seed":"DBAPULSE_PHASE8_MOCK"}'),
       (N'JobFailure', @ServerId, NULL, REPLICATE('6', 64), DATEADD(MINUTE, -35, @SeedAtUtc), DATEADD(MINUTE, -35, @SeedAtUtc), 0, N'Resolved', N'Critical', 1, NULL, N'Mock Nightly ETL failed', N'Mock SQL Agent job failure occurrence.', NULL, @SeedAtUtc, @SeedAtUtc, N'{"seed":"DBAPULSE_PHASE8_MOCK"}'),
       (N'CapacityRisk', @ServerId, @DatabaseId2, REPLICATE('7', 64), DATEADD(DAY, -1, @SeedAtUtc), @SeedAtUtc, 86400000, N'Active', N'Warning', 2, NULL, N'Mock capacity growth risk', N'Mock database growth exceeds its historical baseline.', NULL, @SeedAtUtc, @SeedAtUtc, N'{"seed":"DBAPULSE_PHASE8_MOCK"}');
SELECT TOP (1) @EventId = Id FROM dbo.OperationalEvents WHERE ServerId = @ServerId AND Fingerprint = REPLICATE('1', 64);

INSERT dbo.ManagementCorrelationGroups (GroupFingerprint, ServerId, DatabaseId, WindowStartUtc, WindowEndUtc, LastSeenAtUtc, SignalCount, Status, CreatedAtUtc, UpdatedAtUtc)
VALUES (REPLICATE('8', 64), @ServerId, @DatabaseId, DATEADD(MINUTE, -12, @SeedAtUtc), @SeedAtUtc, @SeedAtUtc, 2, N'Active', @SeedAtUtc, @SeedAtUtc);
SET @GroupId = CONVERT(bigint, SCOPE_IDENTITY());

INSERT dbo.ManagementRelatedSignals (CorrelationGroupId, SignalType, Domain, SignalId, ServerId, DatabaseId, Severity, Status, StartedAtUtc, LastSeenAtUtc, Title, SourceType, CorrelationStrength, TimeDifferenceSeconds, CreatedAtUtc)
VALUES (@GroupId, N'OperationalEvent', N'Performance', @EventId, @ServerId, @DatabaseId, N'Critical', N'Active', DATEADD(MINUTE, -8, @SeedAtUtc), @SeedAtUtc, N'Mock blocking signal', N'OperationalEvents', N'Strong', 0, @SeedAtUtc);

INSERT dbo.AuditLogs (OccurredAtUtc, UserName, UserRole, Action, ResourceType, ResourceId, HttpMethod, RequestPath, Result, StatusCode, DurationMs, CorrelationId, ClientIp, UserAgent, AdditionalData)
VALUES (@SeedAtUtc, N'mock.operator', N'Unauthenticated', N'Operations.EventList.View', N'OperationalEvent', CONVERT(nvarchar(128), @EventId), N'GET', N'/api/operations/events', N'Success', 200, 18, N'mock-correlation-phase8', N'127.0.0.1', N'DBAPulse mock seed', N'{"seed":"DBAPULSE_PHASE8_MOCK"}');

IF NOT EXISTS (SELECT 1 FROM dbo.BackupPolicies WHERE PolicyName = N'Mock Lab Policy')
    INSERT dbo.BackupPolicies (PolicyName, FullBackupMaxAgeHours, DifferentialBackupMaxAgeHours, LogBackupMaxAgeMinutes, WarningPercentage, IsEnabled)
    VALUES (N'Mock Lab Policy', 12, NULL, 30, 80, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.AnomalyPolicies WHERE MetricType = N'MockDuration')
    INSERT dbo.AnomalyPolicies (MetricType, WarningPercentile, CriticalPercentile, WarningModifiedZ, CriticalModifiedZ, MinObservedValue, IsEnabled)
    VALUES (N'MockDuration', .95, .99, 3, 6, 1, 1);

IF NOT EXISTS (SELECT 1 FROM dbo.WaitTypeExclusions WHERE WaitType = N'MOCK_BACKGROUND_WAIT')
    INSERT dbo.WaitTypeExclusions (WaitType, Reason, IsEnabled)
    VALUES (N'MOCK_BACKGROUND_WAIT', N'Mock-only excluded background wait', 1);

COMMIT TRANSACTION;
PRINT N'DBAPULSE mock data inserted. Marker: DBAPULSE_PHASE8_MOCK / DBAPULSE-MOCK-SQL01';
