/*
   Align Protection & Availability overview cards with the server filter used
   by the detail lists. The previous procedure always returned estate-wide
   KPI values while the backup, Always On and Job lists could be server-scoped.
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
        INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
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
                        OR (UPPER(c.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL
                            AND (c.LastLog IS NULL OR DATEDIFF(MINUTE, c.LastLog, @NowSource) > @LogMaxAgeMinutes))
                       THEN N'Critical'
                   WHEN (DATEDIFF(MINUTE, c.LastDataBackup, @NowSource) >= CASE
                              WHEN c.LastDiff IS NOT NULL AND (c.LastFull IS NULL OR c.LastDiff > c.LastFull)
                              THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END * 60 * @WarningPercentage / 100)
                        OR (UPPER(c.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL
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
