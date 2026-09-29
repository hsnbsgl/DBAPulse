/*
   Server environment and backup scope.
   - Prod requires protection for every active user database.
   - Dev/Test/Stage require protection only for databases explicitly marked Required.
   - Mirrored databases and tempdb are always NotApplicable.
   - No source SQL object is created by this migration.
*/

IF COL_LENGTH(N'dbo.Servers', N'Environment') IS NULL
    ALTER TABLE dbo.Servers ADD Environment nvarchar(20) NOT NULL CONSTRAINT DF_Servers_Environment DEFAULT N'Dev';
GO

IF COL_LENGTH(N'dbo.Servers', N'LastBackupCollectionAtUtc') IS NULL
    ALTER TABLE dbo.Servers ADD LastBackupCollectionAtUtc datetime2(3) NULL;
GO

IF COL_LENGTH(N'dbo.Databases', N'BackupProtectionMode') IS NULL
    ALTER TABLE dbo.Databases ADD BackupProtectionMode nvarchar(20) NOT NULL CONSTRAINT DF_Databases_BackupProtectionMode DEFAULT N'Auto';
GO

IF COL_LENGTH(N'dbo.Databases', N'IsMirrored') IS NULL
    ALTER TABLE dbo.Databases ADD IsMirrored bit NOT NULL CONSTRAINT DF_Databases_IsMirrored DEFAULT (0);
GO

IF COL_LENGTH(N'dbo.Databases', N'MirroringRole') IS NULL
    ALTER TABLE dbo.Databases ADD MirroringRole nvarchar(30) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Servers_Environment')
    ALTER TABLE dbo.Servers ADD CONSTRAINT CK_Servers_Environment CHECK (Environment IN (N'Dev', N'Test', N'Stage', N'Prod'));
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Databases_BackupProtectionMode')
    ALTER TABLE dbo.Databases ADD CONSTRAINT CK_Databases_BackupProtectionMode CHECK (BackupProtectionMode IN (N'Auto', N'Required', N'Excluded'));
GO

IF TYPE_ID(N'dbo.DatabaseInputTypeV2') IS NULL
BEGIN
    EXEC(N'CREATE TYPE dbo.DatabaseInputTypeV2 AS TABLE
    (
        ServerId int NOT NULL,
        DatabaseName nvarchar(256) NOT NULL,
        RecoveryModel nvarchar(60) NOT NULL,
        DatabaseStatus nvarchar(60) NOT NULL,
        LastSeenAtUtc datetime2(3) NOT NULL,
        IsActive bit NOT NULL,
        IsMirrored bit NOT NULL,
        MirroringRole nvarchar(30) NULL,
        PRIMARY KEY (ServerId, DatabaseName)
    );');
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Databases_Sync_V2
    @Rows dbo.DatabaseInputTypeV2 READONLY
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d
       SET d.RecoveryModel = r.RecoveryModel,
           d.DatabaseStatus = r.DatabaseStatus,
           d.LastSeenAtUtc = r.LastSeenAtUtc,
           d.IsActive = r.IsActive,
           d.IsMirrored = r.IsMirrored,
           d.MirroringRole = r.MirroringRole
    FROM dbo.Databases AS d
    INNER JOIN @Rows AS r ON r.ServerId = d.ServerId AND r.DatabaseName = d.DatabaseName;

    INSERT dbo.Databases (ServerId, DatabaseName, RecoveryModel, DatabaseStatus, LastSeenAtUtc, IsActive, IsMirrored, MirroringRole)
    SELECT r.ServerId, r.DatabaseName, r.RecoveryModel, r.DatabaseStatus, r.LastSeenAtUtc, r.IsActive, r.IsMirrored, r.MirroringRole
    FROM @Rows AS r
    WHERE NOT EXISTS
    (
        SELECT 1 FROM dbo.Databases AS d
        WHERE d.ServerId = r.ServerId AND d.DatabaseName = r.DatabaseName
    );

    SELECT d.Id, d.ServerId, d.DatabaseName
    FROM dbo.Databases AS d
    INNER JOIN @Rows AS r ON r.ServerId = d.ServerId AND r.DatabaseName = d.DatabaseName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BackupCollection_MarkSuccess
    @ServerId int,
    @CollectedAtUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Servers
       SET LastBackupCollectionAtUtc = @CollectedAtUtc
     WHERE Id = @ServerId;
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
               s.Id AS ServerId,
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
        INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
        LEFT JOIN Latest AS l ON l.DatabaseId = d.Id
        WHERE d.IsActive = 1
        GROUP BY d.Id, d.DatabaseName, s.ServerName, s.Id, s.Environment, d.RecoveryModel, d.DatabaseStatus,
                 d.BackupProtectionMode, d.IsMirrored, s.LastBackupCollectionAtUtc
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
               CASE WHEN s.LastDiff IS NOT NULL AND (s.LastFull IS NULL OR s.LastDiff > s.LastFull) THEN s.LastDiff ELSE s.LastFull END AS LastDataBackup,
               CASE WHEN s.LastDiff IS NOT NULL AND (s.LastFull IS NULL OR s.LastDiff > s.LastFull) THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END AS DataBackupMaxAgeHours
        FROM Scoped AS s
    )
    SELECT e.*,
           CASE
               WHEN e.DatabaseName = N'tempdb' THEN N'NotApplicable'
               WHEN e.IsMirrored = 1 THEN N'NotApplicable'
               WHEN e.BackupRequired = 0 THEN N'NotApplicable'
               WHEN e.LastCollected IS NULL THEN N'Unknown'
               WHEN e.LastDataBackup IS NULL THEN N'NeverBackedUp'
               WHEN (e.DataBackupMaxAgeHours IS NOT NULL AND DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) > e.DataBackupMaxAgeHours * 60)
                    OR (UPPER(e.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL AND (e.LastLog IS NULL OR DATEDIFF(MINUTE, e.LastLog, @NowSource) > @LogMaxAgeMinutes)) THEN N'Critical'
               WHEN (e.DataBackupMaxAgeHours IS NOT NULL AND DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) >= e.DataBackupMaxAgeHours * 60 * @WarningPercentage / 100)
                    OR (UPPER(e.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL AND e.LastLog IS NOT NULL AND DATEDIFF(MINUTE, e.LastLog, @NowSource) >= @LogMaxAgeMinutes * @WarningPercentage / 100) THEN N'Warning'
               ELSE N'Protected'
           END AS ProtectionStatus,
           DATEDIFF(MINUTE, e.LastDataBackup, @NowSource) AS BackupAgeMinutes,
           DATEDIFF(MINUTE, e.LastLog, @NowSource) AS LogBackupAgeMinutes,
           CASE WHEN e.LastCollected IS NULL THEN N'Unknown' WHEN e.LastCollected < DATEADD(MINUTE, -30, SYSUTCDATETIME()) THEN N'Stale' ELSE N'Fresh' END AS DataFreshness,
           CASE WHEN e.DatabaseName = N'tempdb' THEN N'System database'
                WHEN e.IsMirrored = 1 THEN N'Mirrored database'
                WHEN e.Environment = N'Prod' THEN N'Prod policy: all user databases'
                WHEN e.BackupProtectionMode = N'Required' THEN N'Explicitly selected'
                ELSE N'Not selected for backup protection' END AS ProtectionScopeReason
    INTO #Protection
    FROM Evaluated AS e;

    SELECT DatabaseId, DatabaseName, ServerName, RecoveryModel, DatabaseStatus, ProtectionStatus,
           LastFull, LastDiff, LastLog, BackupAgeMinutes, LogBackupAgeMinutes, LastCollected, DataFreshness,
           Environment, BackupProtectionMode, BackupRequired, IsMirrored, ProtectionScopeReason
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

    ;WITH Latest AS
    (
        SELECT b.*,
               ROW_NUMBER() OVER (PARTITION BY b.DatabaseId, b.BackupType ORDER BY b.CollectedAtUtc DESC, b.Id DESC) AS rn
        FROM dbo.BackupSnapshots AS b
    ), Aggregated AS
    (
        SELECT d.Id AS DatabaseId, d.DatabaseName, s.Environment, d.RecoveryModel, d.DatabaseStatus, d.BackupProtectionMode, d.IsMirrored,
               s.LastBackupCollectionAtUtc AS LastCollected,
               MAX(CASE WHEN l.BackupType = N'FULL' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastFull,
               MAX(CASE WHEN l.BackupType = N'DIFFERENTIAL' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastDiff,
               MAX(CASE WHEN l.BackupType = N'LOG' AND l.rn = 1 THEN l.BackupFinishAtSource END) AS LastLog
        FROM dbo.Databases AS d
        INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
        LEFT JOIN Latest AS l ON l.DatabaseId = d.Id
        WHERE d.IsActive = 1
        GROUP BY d.Id, d.DatabaseName, s.Environment, d.RecoveryModel, d.DatabaseStatus, d.BackupProtectionMode, d.IsMirrored, s.LastBackupCollectionAtUtc
    ), Classified AS
    (
        SELECT a.*,
               CAST(CASE WHEN a.DatabaseName = N'tempdb' OR a.IsMirrored = 1 THEN 0 WHEN a.Environment = N'Prod' THEN 1 WHEN a.BackupProtectionMode = N'Required' THEN 1 ELSE 0 END AS bit) AS BackupRequired,
               CASE WHEN a.LastDiff IS NOT NULL AND (a.LastFull IS NULL OR a.LastDiff > a.LastFull) THEN a.LastDiff ELSE a.LastFull END AS LastDataBackup
        FROM Aggregated AS a
    ), Statuses AS
    (
        SELECT c.*,
               CASE
                   WHEN c.DatabaseName = N'tempdb' OR c.IsMirrored = 1 OR c.BackupRequired = 0 THEN N'NotApplicable'
                   WHEN c.LastCollected IS NULL THEN N'Unknown'
                   WHEN c.LastDataBackup IS NULL THEN N'NeverBackedUp'
                   WHEN (DATEDIFF(MINUTE, c.LastDataBackup, @NowSource) > CASE WHEN c.LastDiff IS NOT NULL AND (c.LastFull IS NULL OR c.LastDiff > c.LastFull) THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END * 60)
                        OR (UPPER(c.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL AND (c.LastLog IS NULL OR DATEDIFF(MINUTE, c.LastLog, @NowSource) > @LogMaxAgeMinutes)) THEN N'Critical'
                   WHEN (DATEDIFF(MINUTE, c.LastDataBackup, @NowSource) >= CASE WHEN c.LastDiff IS NOT NULL AND (c.LastFull IS NULL OR c.LastDiff > c.LastFull) THEN @DifferentialMaxAgeHours ELSE @FullMaxAgeHours END * 60 * @WarningPercentage / 100)
                        OR (UPPER(c.RecoveryModel) <> N'SIMPLE' AND @LogMaxAgeMinutes IS NOT NULL AND c.LastLog IS NOT NULL AND DATEDIFF(MINUTE, c.LastLog, @NowSource) >= @LogMaxAgeMinutes * @WarningPercentage / 100) THEN N'Warning'
                   ELSE N'Protected'
               END AS ProtectionStatus
        FROM Classified AS c
    )
    SELECT
        SUM(CASE WHEN ProtectionStatus = N'Protected' THEN 1 ELSE 0 END) AS ProtectedDatabaseCount,
        SUM(CASE WHEN ProtectionStatus = N'Warning' THEN 1 ELSE 0 END) AS BackupWarningCount,
        SUM(CASE WHEN ProtectionStatus IN (N'Critical', N'NeverBackedUp') THEN 1 ELSE 0 END) AS BackupCriticalCount,
        SUM(CASE WHEN ProtectionStatus = N'Unknown' THEN 1 ELSE 0 END) AS BackupUnknownCount,
        (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.AlwaysOnSnapshots x) AND a.SynchronizationHealth IN (N'HEALTHY',N'PARTIALLY_HEALTHY')) AS AlwaysOnHealthyCount,
        (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.AlwaysOnSnapshots x) AND a.SynchronizationHealth = N'PARTIALLY_HEALTHY') AS AlwaysOnWarningCount,
        (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.AlwaysOnSnapshots x) AND (a.IsSuspended = 1 OR a.ConnectedState = N'DISCONNECTED' OR a.SynchronizationHealth = N'NOT_HEALTHY')) AS AlwaysOnCriticalCount,
        (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.JobSnapshots x) AND j.LastRunStatus = N'Failed') AS FailedJobCount,
        (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.JobSnapshots x) AND j.IsRunning = 1) AS RunningJobCount,
        (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc = (SELECT MAX(x.CollectedAtUtc) FROM dbo.JobSnapshots x) AND j.IsRunning = 1 AND j.CurrentDurationSeconds > 1800) AS LongRunningJobCount
    FROM Statuses;
END;
GO
