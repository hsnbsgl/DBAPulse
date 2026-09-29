/*
   Protection semantics:
   - A recent FULL or DIFFERENTIAL backup is the current data-protection signal.
   - A recent DIFFERENTIAL backup is sufficient for freshness; FULL is not
     required again within the same policy window.
   - FULL/BULK_LOGGED databases still require a recent LOG backup when the
     policy defines a log-backup age.
   - A differential without an observed full is accepted as a protection
     signal because the collector may not retain the base-full history. The
     restore-chain validity remains a DBA/source responsibility.
*/

IF OBJECT_ID(N'dbo.BackupPolicies', N'U') IS NOT NULL
BEGIN
    UPDATE dbo.BackupPolicies
    SET DifferentialBackupMaxAgeHours = 24,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE PolicyName = N'Default'
      AND DifferentialBackupMaxAgeHours IS NULL;
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
               ROW_NUMBER() OVER
               (
                   PARTITION BY b.DatabaseId, b.BackupType
                   ORDER BY b.CollectedAtUtc DESC, b.Id DESC
               ) AS rn
        FROM dbo.BackupSnapshots AS b
    ), Aggregated AS
    (
        SELECT d.Id AS DatabaseId,
               d.DatabaseName,
               s.ServerName,
               d.ServerId,
               d.RecoveryModel,
               d.DatabaseStatus,
               MAX(CASE WHEN l.BackupType = N'FULL' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastFull,
               MAX(CASE WHEN l.BackupType = N'DIFFERENTIAL' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastDiff,
               MAX(CASE WHEN l.BackupType = N'LOG' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastLog,
               MAX(l.CollectedAtUtc) AS LastCollected
        FROM dbo.Databases AS d
        INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
        LEFT JOIN Latest AS l ON l.DatabaseId = d.Id
        WHERE d.IsActive = 1
        GROUP BY d.Id, d.DatabaseName, s.ServerName, d.ServerId, d.RecoveryModel, d.DatabaseStatus
    ), Evaluated AS
    (
        SELECT a.*,
               CASE WHEN a.LastDiff IS NOT NULL AND (a.LastFull IS NULL OR a.LastDiff > a.LastFull)
                    THEN a.LastDiff ELSE a.LastFull END AS LastDataBackup,
               CASE WHEN a.LastDiff IS NOT NULL AND (a.LastFull IS NULL OR a.LastDiff > a.LastFull)
                    THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END AS DataBackupMaxAgeHours
        FROM Aggregated AS a
    )
    SELECT e.*,
           CASE
               WHEN e.DatabaseName = N'tempdb' THEN N'NotApplicable'
               WHEN e.LastCollected IS NULL THEN N'Unknown'
               WHEN e.LastDataBackup IS NULL THEN N'NeverBackedUp'
               WHEN
                    (e.DataBackupMaxAgeHours IS NOT NULL AND DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) > e.DataBackupMaxAgeHours * 60)
                    OR (UPPER(e.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL AND
                        (e.LastLog IS NULL OR DATEDIFF(MINUTE, e.LastLog, @NowSource) > @LogMaxAgeMinutes))
                    THEN N'Critical'
               WHEN
                    (e.DataBackupMaxAgeHours IS NOT NULL AND DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) >= e.DataBackupMaxAgeHours * 60 * @WarningPercentage / 100)
                    OR (UPPER(e.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL AND e.LastLog IS NOT NULL AND
                        DATEDIFF(MINUTE, e.LastLog, @NowSource) >= @LogMaxAgeMinutes * @WarningPercentage / 100)
                    THEN N'Warning'
               ELSE N'Protected'
           END AS ProtectionStatus,
           DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) AS BackupAgeMinutes,
           DATEDIFF(MINUTE, e.LastLog, @NowSource) AS LogBackupAgeMinutes,
           CASE
               WHEN e.LastCollected IS NULL THEN N'Unknown'
               WHEN e.LastCollected < DATEADD(MINUTE, -30, SYSUTCDATETIME()) THEN N'Stale'
               ELSE N'Fresh'
           END AS DataFreshness
    INTO #Protection
    FROM Evaluated AS e;

    SELECT DatabaseId, DatabaseName, ServerName, RecoveryModel, DatabaseStatus,
           ProtectionStatus, LastFull, LastDiff, LastLog,
           BackupAgeMinutes, LogBackupAgeMinutes, LastCollected, DataFreshness
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

CREATE OR ALTER PROCEDURE dbo.usp_ProtectionAvailability_Overview
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

    ;WITH Aggregated AS
    (
        SELECT d.Id AS DatabaseId,
               d.DatabaseName,
               d.RecoveryModel,
               d.DatabaseStatus,
               MAX(CASE WHEN b.BackupType = N'FULL' THEN b.BackupFinishAtSource END) AS LastFull,
               MAX(CASE WHEN b.BackupType = N'DIFFERENTIAL' THEN b.BackupFinishAtSource END) AS LastDiff,
               MAX(CASE WHEN b.BackupType = N'LOG' THEN b.BackupFinishAtSource END) AS LastLog,
               MAX(b.CollectedAtUtc) AS LastCollected
        FROM dbo.Databases AS d
        LEFT JOIN dbo.BackupSnapshots AS b ON b.DatabaseId = d.Id
        WHERE d.IsActive = 1
        GROUP BY d.Id, d.DatabaseName, d.RecoveryModel, d.DatabaseStatus
    ), Evaluated AS
    (
        SELECT a.*,
               CASE WHEN a.LastDiff IS NOT NULL AND (a.LastFull IS NULL OR a.LastDiff > a.LastFull)
                    THEN a.LastDiff ELSE a.LastFull END AS LastDataBackup,
               CASE WHEN a.LastDiff IS NOT NULL AND (a.LastFull IS NULL OR a.LastDiff > a.LastFull)
                    THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END AS DataBackupMaxAgeHours
        FROM Aggregated AS a
    ), Classified AS
    (
        SELECT e.*,
               CASE
                   WHEN e.DatabaseName = N'tempdb' THEN N'NotApplicable'
                   WHEN e.LastCollected IS NULL THEN N'Unknown'
                   WHEN e.LastDataBackup IS NULL THEN N'NeverBackedUp'
                   WHEN
                        (e.DataBackupMaxAgeHours IS NOT NULL AND DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) > e.DataBackupMaxAgeHours * 60)
                        OR (UPPER(e.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL AND
                            (e.LastLog IS NULL OR DATEDIFF(MINUTE, e.LastLog, @NowSource) > @LogMaxAgeMinutes))
                        THEN N'Critical'
                   WHEN
                        (e.DataBackupMaxAgeHours IS NOT NULL AND DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) >= e.DataBackupMaxAgeHours * 60 * @WarningPercentage / 100)
                        OR (UPPER(e.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL AND e.LastLog IS NOT NULL AND
                            DATEDIFF(MINUTE, e.LastLog, @NowSource) >= @LogMaxAgeMinutes * @WarningPercentage / 100)
                        THEN N'Warning'
                   ELSE N'Protected'
               END AS ProtectionStatus
        FROM Evaluated AS e
    )
    SELECT
        SUM(CASE WHEN ProtectionStatus = N'Protected' THEN 1 ELSE 0 END) AS ProtectedDatabaseCount,
        SUM(CASE WHEN ProtectionStatus = N'Warning' THEN 1 ELSE 0 END) AS BackupWarningCount,
        SUM(CASE WHEN ProtectionStatus = N'Critical' THEN 1 ELSE 0 END) AS BackupCriticalCount,
        SUM(CASE WHEN ProtectionStatus = N'Unknown' THEN 1 ELSE 0 END) AS BackupUnknownCount,
        (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.AlwaysOnSnapshots x) AND a.SynchronizationHealth IN (N'HEALTHY',N'PARTIALLY_HEALTHY')) AS AlwaysOnHealthyCount,
        (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.AlwaysOnSnapshots x) AND a.SynchronizationHealth = N'PARTIALLY_HEALTHY') AS AlwaysOnWarningCount,
        (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.AlwaysOnSnapshots x) AND (a.IsSuspended = 1 OR a.ConnectedState = N'DISCONNECTED' OR a.SynchronizationHealth = N'NOT_HEALTHY')) AS AlwaysOnCriticalCount,
        (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.JobSnapshots x) AND j.LastRunStatus = N'Failed') AS FailedJobCount,
        (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.JobSnapshots x) AND j.IsRunning = 1) AS RunningJobCount,
        (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.JobSnapshots x) AND j.IsRunning = 1 AND j.CurrentDurationSeconds > 1800) AS LongRunningJobCount
    FROM Classified;
END;
GO
