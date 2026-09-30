/*
   Protection, Always On and Job health must use the same active-server
   scope. Inactive/mock servers remain in raw telemetry but are excluded from
   operational lists and KPI calculations.

   Log backup policy:
   - Prod FULL/BULK_LOGGED databases require a recent log backup.
   - Dev/Test/Stage FULL/BULK_LOGGED databases are evaluated by data backup
     freshness only; log backup age is informational and does not create risk.
*/

CREATE OR ALTER PROCEDURE dbo.usp_ProtectionAvailability_Overview
    @ServerId int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NowSource datetime2(3) = GETDATE();
    DECLARE @FullMaxAgeHours int = 24;
    DECLARE @DifferentialMaxAgeHours int = 24;
    DECLARE @LogMaxAgeMinutes int = 60;
    DECLARE @WarningPercentage int = 80;

    SELECT TOP (1)
        @FullMaxAgeHours = p.FullBackupMaxAgeHours,
        @DifferentialMaxAgeHours = p.DifferentialBackupMaxAgeHours,
        @LogMaxAgeMinutes = p.LogBackupMaxAgeMinutes,
        @WarningPercentage = p.WarningPercentage
    FROM dbo.BackupPolicies AS p
    WHERE p.IsEnabled = 1
    ORDER BY CASE WHEN p.PolicyName = N'Default' THEN 0 ELSE 1 END, p.Id;

    SET @WarningPercentage = CASE WHEN @WarningPercentage BETWEEN 1 AND 99 THEN @WarningPercentage ELSE 80 END;

    ;WITH LatestBackup AS
    (
        SELECT b.*,
               ROW_NUMBER() OVER
               (
                   PARTITION BY b.DatabaseId, b.BackupType
                   ORDER BY b.CollectedAtUtc DESC, b.Id DESC
               ) AS rn
        FROM dbo.BackupSnapshots AS b
    ), Aggregated AS
    (
        SELECT d.Id AS DatabaseId,
               d.ServerId,
               d.DatabaseName,
               s.Environment,
               d.RecoveryModel,
               d.DatabaseStatus,
               d.BackupProtectionMode,
               d.IsMirrored,
               s.LastBackupCollectionAtUtc AS LastCollected,
               MAX(CASE WHEN b.BackupType = N'FULL' AND b.rn = 1 THEN b.BackupFinishAtSource END) AS LastFull,
               MAX(CASE WHEN b.BackupType = N'DIFFERENTIAL' AND b.rn = 1 THEN b.BackupFinishAtSource END) AS LastDiff,
               MAX(CASE WHEN b.BackupType = N'LOG' AND b.rn = 1 THEN b.BackupFinishAtSource END) AS LastLog
        FROM dbo.Databases AS d
        INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId AND s.IsActive = 1
        LEFT JOIN LatestBackup AS b ON b.DatabaseId = d.Id
        WHERE d.IsActive = 1
        GROUP BY d.Id, d.ServerId, d.DatabaseName, s.Environment, d.RecoveryModel,
                 d.DatabaseStatus, d.BackupProtectionMode, d.IsMirrored,
                 s.LastBackupCollectionAtUtc
    ), Classified AS
    (
        SELECT a.*,
               CAST(CASE
                   WHEN a.DatabaseName = N'tempdb' OR a.IsMirrored = 1 THEN 0
                   WHEN a.Environment = N'Prod' THEN 1
                   WHEN a.BackupProtectionMode = N'Required' THEN 1
                   ELSE 0
               END AS bit) AS BackupRequired,
               CASE WHEN a.LastDiff IS NOT NULL AND (a.LastFull IS NULL OR a.LastDiff > a.LastFull)
                    THEN a.LastDiff ELSE a.LastFull END AS LastDataBackup
        FROM Aggregated AS a
    ), Statuses AS
    (
        SELECT c.*,
               CASE
                   WHEN c.DatabaseName = N'tempdb' OR c.IsMirrored = 1 OR c.BackupRequired = 0 THEN N'NotApplicable'
                   WHEN c.LastCollected IS NULL THEN N'Unknown'
                   WHEN c.LastDataBackup IS NULL THEN N'NeverBackedUp'
                   WHEN (DATEDIFF(MINUTE, c.LastDataBackup, @NowSource) > CASE
                              WHEN c.LastDiff IS NOT NULL AND (c.LastFull IS NULL OR c.LastDiff > c.LastFull)
                              THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END * 60)
                        OR (UPPER(c.RecoveryModel) <> N'SIMPLE' AND c.Environment = N'Prod' AND @LogMaxAgeMinutes IS NOT NULL
                            AND (c.LastLog IS NULL OR DATEDIFF(MINUTE, c.LastLog, @NowSource) > @LogMaxAgeMinutes))
                       THEN N'Critical'
                   WHEN (DATEDIFF(MINUTE, c.LastDataBackup, @NowSource) >= CASE
                              WHEN c.LastDiff IS NOT NULL AND (c.LastFull IS NULL OR c.LastDiff > c.LastFull)
                              THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END * 60 * @WarningPercentage / 100)
                        OR (UPPER(c.RecoveryModel) <> N'SIMPLE' AND c.Environment = N'Prod' AND @LogMaxAgeMinutes IS NOT NULL
                            AND c.LastLog IS NOT NULL
                            AND DATEDIFF(MINUTE, c.LastLog, @NowSource) >= @LogMaxAgeMinutes * @WarningPercentage / 100)
                       THEN N'Warning'
                   ELSE N'Protected'
               END AS ProtectionStatus
        FROM Classified AS c
    ), LatestAlwaysOn AS
    (
        SELECT a.*,
               ROW_NUMBER() OVER
               (
                   PARTITION BY a.ServerId, a.AvailabilityGroupName, a.ReplicaServerName, a.DatabaseName
                   ORDER BY a.CollectedAtUtc DESC, a.Id DESC
               ) AS rn
        FROM dbo.AlwaysOnSnapshots AS a
        INNER JOIN dbo.Servers AS s ON s.Id = a.ServerId AND s.IsActive = 1
        WHERE @ServerId IS NULL OR a.ServerId = @ServerId
    ), LatestJobs AS
    (
        SELECT j.*,
               ROW_NUMBER() OVER
               (
                   PARTITION BY j.ServerId, j.JobId
                   ORDER BY j.CollectedAtUtc DESC, j.Id DESC
               ) AS rn
        FROM dbo.JobSnapshots AS j
        INNER JOIN dbo.Servers AS s ON s.Id = j.ServerId AND s.IsActive = 1
        WHERE @ServerId IS NULL OR j.ServerId = @ServerId
    )
    SELECT
        COUNT(CASE WHEN s.ProtectionStatus = N'Protected' THEN 1 END) AS ProtectedDatabaseCount,
        COUNT(CASE WHEN s.ProtectionStatus = N'Warning' THEN 1 END) AS BackupWarningCount,
        COUNT(CASE WHEN s.ProtectionStatus IN (N'Critical', N'NeverBackedUp') THEN 1 END) AS BackupCriticalCount,
        COUNT(CASE WHEN s.ProtectionStatus = N'Unknown' THEN 1 END) AS BackupUnknownCount,
        (SELECT COUNT(CASE WHEN a.SynchronizationHealth = N'HEALTHY' THEN 1 END)
           FROM LatestAlwaysOn AS a WHERE a.rn = 1) AS AlwaysOnHealthyCount,
        (SELECT COUNT(CASE WHEN a.SynchronizationHealth = N'PARTIALLY_HEALTHY' THEN 1 END)
           FROM LatestAlwaysOn AS a WHERE a.rn = 1) AS AlwaysOnWarningCount,
        (SELECT COUNT(CASE WHEN a.IsSuspended = 1
                                OR a.ConnectedState = N'DISCONNECTED'
                                OR a.SynchronizationHealth = N'NOT_HEALTHY' THEN 1 END)
           FROM LatestAlwaysOn AS a WHERE a.rn = 1) AS AlwaysOnCriticalCount,
        (SELECT COUNT(CASE WHEN j.LastRunStatus = N'Failed' THEN 1 END)
           FROM LatestJobs AS j WHERE j.rn = 1) AS FailedJobCount,
        (SELECT COUNT(CASE WHEN j.IsRunning = 1 THEN 1 END)
           FROM LatestJobs AS j WHERE j.rn = 1) AS RunningJobCount,
        (SELECT COUNT(CASE WHEN j.IsRunning = 1 AND j.CurrentDurationSeconds > 1800 THEN 1 END)
           FROM LatestJobs AS j WHERE j.rn = 1) AS LongRunningJobCount
    FROM Statuses AS s
    WHERE @ServerId IS NULL OR s.ServerId = @ServerId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BackupProtection_List
    @Status nvarchar(30) = NULL,
    @ServerId int = NULL,
    @DatabaseId int = NULL,
    @RecoveryModel nvarchar(60) = NULL,
    @PageNumber int = 1,
    @PageSize int = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageSize = CASE WHEN @PageSize > 100 THEN 100 WHEN @PageSize < 1 THEN 1 ELSE @PageSize END;
    SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;

    DECLARE @NowSource datetime2(3) = GETDATE();
    DECLARE @FullMaxAgeHours int = 24;
    DECLARE @DifferentialMaxAgeHours int = 24;
    DECLARE @LogMaxAgeMinutes int = 60;
    DECLARE @WarningPercentage int = 80;

    SELECT TOP (1)
        @FullMaxAgeHours = p.FullBackupMaxAgeHours,
        @DifferentialMaxAgeHours = p.DifferentialBackupMaxAgeHours,
        @LogMaxAgeMinutes = p.LogBackupMaxAgeMinutes,
        @WarningPercentage = p.WarningPercentage
    FROM dbo.BackupPolicies AS p
    WHERE p.IsEnabled = 1
    ORDER BY CASE WHEN p.PolicyName = N'Default' THEN 0 ELSE 1 END, p.Id;

    SET @WarningPercentage = CASE WHEN @WarningPercentage BETWEEN 1 AND 99 THEN @WarningPercentage ELSE 80 END;

    ;WITH Latest AS
    (
        SELECT b.*,
               ROW_NUMBER() OVER (PARTITION BY b.DatabaseId, b.BackupType ORDER BY b.CollectedAtUtc DESC, b.Id DESC) AS rn
        FROM dbo.BackupSnapshots AS b
    ), Aggregated AS
    (
        SELECT d.Id AS DatabaseId,
               d.DatabaseName,
               s.ServerName,
               d.ServerId,
               s.Environment,
               d.RecoveryModel,
               d.DatabaseStatus,
               d.BackupProtectionMode,
               d.IsMirrored,
               s.LastBackupCollectionAtUtc AS LastCollected,
               MAX(CASE WHEN l.BackupType = N'FULL' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastFull,
               MAX(CASE WHEN l.BackupType = N'DIFFERENTIAL' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastDiff,
               MAX(CASE WHEN l.BackupType = N'LOG' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastLog
        FROM dbo.Databases AS d
        INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId AND s.IsActive = 1
        LEFT JOIN Latest AS l ON l.DatabaseId = d.Id
        WHERE d.IsActive = 1
        GROUP BY d.Id, d.DatabaseName, s.ServerName, d.ServerId, s.Environment, d.RecoveryModel,
                 d.DatabaseStatus, d.BackupProtectionMode, d.IsMirrored, s.LastBackupCollectionAtUtc
    ), Scoped AS
    (
        SELECT a.*,
               CAST(CASE WHEN a.DatabaseName = N'tempdb' OR a.IsMirrored = 1 THEN 0
                         WHEN a.Environment = N'Prod' THEN 1
                         WHEN a.BackupProtectionMode = N'Required' THEN 1
                         ELSE 0 END AS bit) AS BackupRequired
        FROM Aggregated AS a
    ), Evaluated AS
    (
        SELECT s.*,
               CASE WHEN s.LastDiff IS NOT NULL AND (s.LastFull IS NULL OR s.LastDiff > s.LastFull)
                    THEN s.LastDiff ELSE s.LastFull END AS LastDataBackup,
               CASE WHEN s.LastDiff IS NOT NULL AND (s.LastFull IS NULL OR s.LastDiff > s.LastFull)
                    THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END AS DataBackupMaxAgeHours
        FROM Scoped AS s
    )
    SELECT e.*,
           CASE
               WHEN e.DatabaseName = N'tempdb' OR e.IsMirrored = 1 OR e.BackupRequired = 0 THEN N'NotApplicable'
               WHEN e.LastCollected IS NULL THEN N'Unknown'
               WHEN e.LastDataBackup IS NULL THEN N'NeverBackedUp'
               WHEN (DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) > e.DataBackupMaxAgeHours * 60)
                    OR (UPPER(e.RecoveryModel) <> N'SIMPLE' AND e.Environment = N'Prod' AND @LogMaxAgeMinutes IS NOT NULL
                        AND (e.LastLog IS NULL OR DATEDIFF(MINUTE, e.LastLog, @NowSource) > @LogMaxAgeMinutes)) THEN N'Critical'
               WHEN (DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) >= e.DataBackupMaxAgeHours * 60 * @WarningPercentage / 100)
                    OR (UPPER(e.RecoveryModel) <> N'SIMPLE' AND e.Environment = N'Prod' AND @LogMaxAgeMinutes IS NOT NULL AND e.LastLog IS NOT NULL
                        AND DATEDIFF(MINUTE, e.LastLog, @NowSource) >= @LogMaxAgeMinutes * @WarningPercentage / 100) THEN N'Warning'
               ELSE N'Protected'
           END AS ProtectionStatus,
           DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) AS BackupAgeMinutes,
           DATEDIFF(MINUTE, e.LastLog, @NowSource) AS LogBackupAgeMinutes,
           CASE WHEN e.LastCollected IS NULL THEN N'Unknown'
                WHEN e.LastCollected < DATEADD(MINUTE, -30, SYSUTCDATETIME()) THEN N'Stale'
                ELSE N'Fresh' END AS DataFreshness,
           CASE WHEN e.DatabaseName = N'tempdb' THEN N'System database'
                WHEN e.IsMirrored = 1 THEN N'Mirrored database'
                WHEN e.Environment = N'Prod' THEN N'Prod policy: all user databases'
                WHEN e.BackupProtectionMode = N'Required' THEN N'Explicitly selected'
                ELSE N'Excluded from backup protection' END AS ProtectionScopeReason
    INTO #Protection
    FROM Evaluated AS e;

    SELECT DatabaseId, DatabaseName, ServerName, RecoveryModel, DatabaseStatus, ProtectionStatus,
           LastFull, LastDiff, LastLog, BackupAgeMinutes, LogBackupAgeMinutes, LastCollected,
           DataFreshness, Environment, BackupProtectionMode, BackupRequired, IsMirrored, ProtectionScopeReason
    FROM #Protection
    WHERE (@ServerId IS NULL OR ServerId = @ServerId)
      AND (@DatabaseId IS NULL OR DatabaseId = @DatabaseId)
      AND (@RecoveryModel IS NULL OR RecoveryModel = @RecoveryModel)
      AND (@Status IS NULL OR ProtectionStatus = @Status)
    ORDER BY DatabaseName
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount
    FROM #Protection
    WHERE (@ServerId IS NULL OR ServerId = @ServerId)
      AND (@DatabaseId IS NULL OR DatabaseId = @DatabaseId)
      AND (@RecoveryModel IS NULL OR RecoveryModel = @RecoveryModel)
      AND (@Status IS NULL OR ProtectionStatus = @Status);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AlwaysOnHealth_List
    @Health nvarchar(30) = NULL,
    @ServerId int = NULL,
    @Role nvarchar(60) = NULL,
    @SynchronizationState nvarchar(60) = NULL,
    @PageNumber int = 1,
    @PageSize int = 50,
    @Id bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageSize = CASE WHEN @PageSize > 100 THEN 100 WHEN @PageSize < 1 THEN 1 ELSE @PageSize END;
    SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;

    ;WITH CurrentRows AS
    (
        SELECT a.Id, a.ServerId, s.ServerName, a.AvailabilityGroupName, a.ReplicaServerName,
               a.RoleDescription AS Role, a.OperationalState, a.ConnectedState,
               a.SynchronizationHealth, a.DatabaseName, a.SynchronizationState, a.DatabaseState,
               a.IsSuspended, a.SuspendReason, a.LogSendQueueMb, a.RedoQueueMb,
               CAST(NULL AS decimal(19,2)) AS EstimatedLagMinutes, a.CollectedAtUtc,
               CASE WHEN a.IsSuspended = 1 OR a.ConnectedState = N'DISCONNECTED'
                          OR a.SynchronizationHealth = N'NOT_HEALTHY' THEN N'Critical'
                    WHEN a.SynchronizationState = N'NOT SYNCHRONIZING'
                          OR a.SynchronizationHealth = N'PARTIALLY_HEALTHY' THEN N'Warning'
                    ELSE N'Healthy' END AS HealthStatus,
               CASE WHEN a.CollectedAtUtc < DATEADD(MINUTE, -30, SYSUTCDATETIME()) THEN N'Stale' ELSE N'Fresh' END AS DataFreshness,
               ROW_NUMBER() OVER
               (
                   PARTITION BY a.ServerId, a.AvailabilityGroupName, a.ReplicaServerName, a.DatabaseName
                   ORDER BY a.CollectedAtUtc DESC, a.Id DESC
               ) AS rn
        FROM dbo.AlwaysOnSnapshots AS a
        INNER JOIN dbo.Servers AS s ON s.Id = a.ServerId AND s.IsActive = 1
        WHERE @ServerId IS NULL OR a.ServerId = @ServerId
    )
    SELECT Id, ServerName, AvailabilityGroupName, ReplicaServerName, Role, OperationalState,
           ConnectedState, SynchronizationHealth, DatabaseName, SynchronizationState, DatabaseState,
           IsSuspended, SuspendReason, LogSendQueueMb, RedoQueueMb, EstimatedLagMinutes,
           CollectedAtUtc, HealthStatus, DataFreshness
    INTO #AlwaysOn
    FROM CurrentRows
    WHERE rn = 1;

    SELECT * FROM #AlwaysOn
    WHERE (@Id IS NULL OR Id = @Id)
      AND (@Role IS NULL OR Role = @Role)
      AND (@SynchronizationState IS NULL OR SynchronizationState = @SynchronizationState)
      AND (@Health IS NULL OR HealthStatus = @Health)
    ORDER BY CollectedAtUtc DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM #AlwaysOn
    WHERE (@Id IS NULL OR Id = @Id)
      AND (@Role IS NULL OR Role = @Role)
      AND (@SynchronizationState IS NULL OR SynchronizationState = @SynchronizationState)
      AND (@Health IS NULL OR HealthStatus = @Health);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_JobHealth_List
    @Status nvarchar(30) = NULL,
    @ServerId int = NULL,
    @Enabled bit = NULL,
    @RepeatedFailure bit = NULL,
    @Running bit = NULL,
    @PageNumber int = 1,
    @PageSize int = 50,
    @Id bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageSize = CASE WHEN @PageSize > 100 THEN 100 WHEN @PageSize < 1 THEN 1 ELSE @PageSize END;
    SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;

    ;WITH CurrentRows AS
    (
        SELECT j.Id, j.ServerId, s.ServerName, COALESCE(j.JobId, N'') AS JobId, j.JobName,
               j.Enabled, j.LastRunStatus, j.LastRunAtSource, j.LastRunDurationSeconds,
               j.IsRunning, j.CurrentStartAtSource, j.CurrentDurationSeconds,
               j.FailureCount24Hours, j.FailureCount7Days, j.RepeatedFailure,
               CAST(CASE WHEN j.IsRunning = 1 AND j.CurrentDurationSeconds > 1800 THEN 1 ELSE 0 END AS bit) AS IsLongRunning,
               j.CollectedAtUtc,
               CASE WHEN j.CollectedAtUtc < DATEADD(MINUTE, -30, SYSUTCDATETIME()) THEN N'Stale' ELSE N'Fresh' END AS DataFreshness,
               ROW_NUMBER() OVER
               (
                   PARTITION BY j.ServerId, COALESCE(j.JobId, j.JobName)
                   ORDER BY j.CollectedAtUtc DESC, j.Id DESC
               ) AS rn
        FROM dbo.JobSnapshots AS j
        INNER JOIN dbo.Servers AS s ON s.Id = j.ServerId AND s.IsActive = 1
        WHERE @ServerId IS NULL OR j.ServerId = @ServerId
    )
    SELECT Id, ServerName, JobId, JobName, Enabled, LastRunStatus, LastRunAtSource,
           LastRunDurationSeconds, IsRunning, CurrentStartAtSource, CurrentDurationSeconds,
           FailureCount24Hours, FailureCount7Days, RepeatedFailure, IsLongRunning,
           CollectedAtUtc, DataFreshness
    INTO #Jobs
    FROM CurrentRows
    WHERE rn = 1;

    SELECT * FROM #Jobs
    WHERE (@Id IS NULL OR Id = @Id)
      AND (@Status IS NULL OR LastRunStatus = @Status)
      AND (@Enabled IS NULL OR Enabled = @Enabled)
      AND (@RepeatedFailure IS NULL OR RepeatedFailure = @RepeatedFailure)
      AND (@Running IS NULL OR IsRunning = @Running)
    ORDER BY JobName
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM #Jobs
    WHERE (@Id IS NULL OR Id = @Id)
      AND (@Status IS NULL OR LastRunStatus = @Status)
      AND (@Enabled IS NULL OR Enabled = @Enabled)
      AND (@RepeatedFailure IS NULL OR RepeatedFailure = @RepeatedFailure)
      AND (@Running IS NULL OR IsRunning = @Running);
END;
GO
