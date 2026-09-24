CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_Overview
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH LastRun AS
    (
        SELECT TOP (1) Id, Status, StartedAtUtc, FinishedAtUtc, DurationMs
        FROM dbo.CollectionRuns ORDER BY Id DESC
    )
    SELECT
        (SELECT COUNT(*) FROM dbo.Servers WHERE IsActive = 1) AS TotalServers,
        (SELECT COUNT(*) FROM dbo.Databases WHERE IsActive = 1) AS TotalDatabases,
        (SELECT COUNT(*) FROM dbo.Databases WHERE IsActive = 1 AND DatabaseStatus = N'ONLINE') AS OnlineDatabases,
        (SELECT COUNT(*) FROM dbo.Databases WHERE IsActive = 1 AND DatabaseStatus NOT IN (N'ONLINE', N'OFFLINE', N'SUSPECT', N'RECOVERY_PENDING', N'EMERGENCY')) AS WarningDatabases,
        (SELECT COUNT(*) FROM dbo.Databases WHERE IsActive = 1 AND DatabaseStatus IN (N'OFFLINE', N'SUSPECT', N'RECOVERY_PENDING', N'EMERGENCY')) AS OfflineDatabases,
        lr.Status AS LastCollectionStatus,
        lr.StartedAtUtc AS LastCollectionStartedAtUtc,
        lr.FinishedAtUtc AS LastCollectionFinishedAtUtc,
        lr.DurationMs AS LastCollectionDurationMs,
        COALESCE((SELECT COUNT(*) FROM dbo.CollectionErrors WHERE CollectionRunId = lr.Id), 0) AS CollectionErrorCount
    FROM LastRun AS lr;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_DatabaseHealth
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.Id AS DatabaseId, d.DatabaseName, s.Id AS ServerId, s.ServerName,
           d.DatabaseStatus, d.RecoveryModel, d.LastSeenAtUtc,
           CASE
               WHEN d.DatabaseStatus = N'ONLINE' THEN N'Healthy'
               WHEN d.DatabaseStatus IN (N'OFFLINE', N'SUSPECT', N'RECOVERY_PENDING', N'EMERGENCY') THEN N'Critical'
               ELSE N'Warning'
           END AS HealthStatus
    FROM dbo.Databases AS d
    INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
    WHERE d.IsActive = 1
    ORDER BY s.ServerName, d.DatabaseName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_BackupStatus
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH Latest AS
    (
        SELECT b.ServerId, b.DatabaseId, b.DatabaseName, b.BackupType, b.BackupFinishAtSource,
               ROW_NUMBER() OVER (PARTITION BY b.ServerId, b.DatabaseName, b.BackupType ORDER BY b.CollectedAtUtc DESC, b.Id DESC) AS rn
        FROM dbo.BackupSnapshots AS b
    )
    SELECT d.Id AS DatabaseId, d.DatabaseName, s.ServerName, d.RecoveryModel,
           MAX(CASE WHEN l.BackupType = N'FULL' THEN l.BackupFinishAtSource END) AS LastFullBackupAtSource,
           MAX(CASE WHEN l.BackupType = N'DIFFERENTIAL' THEN l.BackupFinishAtSource END) AS LastDifferentialBackupAtSource,
           MAX(CASE WHEN l.BackupType = N'LOG' THEN l.BackupFinishAtSource END) AS LastLogBackupAtSource,
           CASE WHEN COUNT(l.DatabaseName) = 0 THEN N'Unknown' ELSE N'Available' END AS BackupStatus
    FROM dbo.Databases AS d
    INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
    LEFT JOIN Latest AS l ON l.DatabaseName = d.DatabaseName AND l.DatabaseId = d.Id AND l.rn = 1
    WHERE d.IsActive = 1
    GROUP BY d.Id, d.DatabaseName, s.ServerName, d.RecoveryModel
    ORDER BY s.ServerName, d.DatabaseName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_Capacity
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH Latest AS
    (
        SELECT c.*, ROW_NUMBER() OVER (PARTITION BY c.DatabaseId, c.FileType ORDER BY c.CollectedAtUtc DESC, c.Id DESC) AS rn
        FROM dbo.CapacitySnapshots AS c
    ), CurrentRows AS
    (
        SELECT l.DatabaseId, l.DatabaseName, l.FileType, l.AllocatedSizeMb, l.CollectedAtUtc, l.ServerId
        FROM Latest AS l WHERE l.rn = 1
    )
    SELECT
        COALESCE(SUM(CASE WHEN FileType = N'ROWS' THEN AllocatedSizeMb ELSE 0 END), 0) AS TotalDataSizeMb,
        COALESCE(SUM(CASE WHEN FileType = N'LOG' THEN AllocatedSizeMb ELSE 0 END), 0) AS TotalLogSizeMb,
        COALESCE(SUM(AllocatedSizeMb), 0) AS TotalDatabaseSizeMb
    FROM CurrentRows;

    SELECT DatabaseId, DatabaseName, ServerId,
           SUM(CASE WHEN FileType = N'ROWS' THEN AllocatedSizeMb ELSE 0 END) AS DataSizeMb,
           SUM(CASE WHEN FileType = N'LOG' THEN AllocatedSizeMb ELSE 0 END) AS LogSizeMb,
           SUM(AllocatedSizeMb) AS TotalSizeMb,
           MAX(CollectedAtUtc) AS CollectedAtUtc
    FROM CurrentRows
    GROUP BY DatabaseId, DatabaseName, ServerId
    ORDER BY DatabaseName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_RecentCollections
    @Limit int = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET @Limit = CASE WHEN @Limit < 1 THEN 1 WHEN @Limit > 100 THEN 100 ELSE @Limit END;
    SELECT TOP (@Limit) r.Id AS CollectionRunId, r.StartedAtUtc, r.FinishedAtUtc, r.Status, r.DurationMs,
           (SELECT COUNT(*) FROM dbo.CollectionErrors AS e WHERE e.CollectionRunId = r.Id) AS ErrorCount
    FROM dbo.CollectionRuns AS r
    ORDER BY r.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Servers_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.Id AS ServerId, s.ServerName, s.InstanceName, s.SqlVersion, s.Edition, s.LastSeenAtUtc,
           COUNT(d.Id) AS DatabaseCount
    FROM dbo.Servers AS s
    LEFT JOIN dbo.Databases AS d ON d.ServerId = s.Id AND d.IsActive = 1
    WHERE s.IsActive = 1
    GROUP BY s.Id, s.ServerName, s.InstanceName, s.SqlVersion, s.Edition, s.LastSeenAtUtc
    ORDER BY s.ServerName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Server_Detail
    @ServerId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.Id AS ServerId, s.ServerName, s.InstanceName, s.SqlVersion, s.Edition, s.TimeZoneId, s.LastSeenAtUtc,
           COUNT(d.Id) AS DatabaseCount
    FROM dbo.Servers AS s
    LEFT JOIN dbo.Databases AS d ON d.ServerId = s.Id AND d.IsActive = 1
    WHERE s.Id = @ServerId
    GROUP BY s.Id, s.ServerName, s.InstanceName, s.SqlVersion, s.Edition, s.TimeZoneId, s.LastSeenAtUtc;

    SELECT d.Id AS DatabaseId, d.DatabaseName, d.DatabaseStatus, d.RecoveryModel, d.LastSeenAtUtc
    FROM dbo.Databases AS d WHERE d.ServerId = @ServerId AND d.IsActive = 1 ORDER BY d.DatabaseName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Databases_List
    @PageNumber int = 1,
    @PageSize int = 50,
    @Search nvarchar(256) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize = CASE WHEN @PageSize < 1 THEN 50 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');

    ;WITH LatestCapacity AS
    (
        SELECT c.*, ROW_NUMBER() OVER (PARTITION BY c.DatabaseId, c.FileType ORDER BY c.CollectedAtUtc DESC, c.Id DESC) AS rn
        FROM dbo.CapacitySnapshots AS c
    ), Capacity AS
    (
        SELECT DatabaseId, SUM(CASE WHEN FileType = N'ROWS' THEN AllocatedSizeMb ELSE 0 END) AS DataSizeMb,
               SUM(CASE WHEN FileType = N'LOG' THEN AllocatedSizeMb ELSE 0 END) AS LogSizeMb,
               SUM(AllocatedSizeMb) AS TotalSizeMb
        FROM LatestCapacity WHERE rn = 1 GROUP BY DatabaseId
    ), LatestBackup AS
    (
        SELECT b.*, ROW_NUMBER() OVER (PARTITION BY b.DatabaseId, b.BackupType ORDER BY b.CollectedAtUtc DESC, b.Id DESC) AS rn
        FROM dbo.BackupSnapshots AS b
    )
    SELECT d.Id AS DatabaseId, d.DatabaseName, s.Id AS ServerId, s.ServerName, d.DatabaseStatus, d.RecoveryModel, d.LastSeenAtUtc,
           c.DataSizeMb AS CurrentDataSizeMb, c.LogSizeMb AS CurrentLogSizeMb, c.TotalSizeMb AS CurrentTotalSizeMb,
           MAX(CASE WHEN b.BackupType = N'FULL' THEN b.BackupFinishAtSource END) AS LastFullBackupAtSource
    FROM dbo.Databases AS d
    INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
    LEFT JOIN Capacity AS c ON c.DatabaseId = d.Id
    LEFT JOIN LatestBackup AS b ON b.DatabaseId = d.Id AND b.rn = 1
    WHERE d.IsActive = 1 AND (@Search IS NULL OR d.DatabaseName LIKE N'%' + @Search + N'%' OR s.ServerName LIKE N'%' + @Search + N'%')
    GROUP BY d.Id, d.DatabaseName, s.Id, s.ServerName, d.DatabaseStatus, d.RecoveryModel, d.LastSeenAtUtc, c.DataSizeMb, c.LogSizeMb, c.TotalSizeMb
    ORDER BY s.ServerName, d.DatabaseName
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM dbo.Databases AS d INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
    WHERE d.IsActive = 1 AND (@Search IS NULL OR d.DatabaseName LIKE N'%' + @Search + N'%' OR s.ServerName LIKE N'%' + @Search + N'%');
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Database_Detail
    @DatabaseId int
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH LatestCapacity AS
    (
        SELECT c.*, ROW_NUMBER() OVER (PARTITION BY c.FileType ORDER BY c.CollectedAtUtc DESC, c.Id DESC) AS rn
        FROM dbo.CapacitySnapshots AS c WHERE c.DatabaseId = @DatabaseId
    ), LatestBackup AS
    (
        SELECT b.*, ROW_NUMBER() OVER (PARTITION BY b.BackupType ORDER BY b.CollectedAtUtc DESC, b.Id DESC) AS rn
        FROM dbo.BackupSnapshots AS b WHERE b.DatabaseId = @DatabaseId
    ), Capacity AS
    (
        SELECT SUM(CASE WHEN FileType = N'ROWS' THEN AllocatedSizeMb ELSE 0 END) AS CurrentDataSizeMb,
               SUM(CASE WHEN FileType = N'LOG' THEN AllocatedSizeMb ELSE 0 END) AS CurrentLogSizeMb,
               SUM(AllocatedSizeMb) AS CurrentTotalSizeMb
        FROM LatestCapacity WHERE rn = 1
    ), BackupAgg AS
    (
        SELECT MAX(CASE WHEN BackupType = N'FULL' THEN BackupFinishAtSource END) AS LastFullBackupAtSource,
               MAX(CASE WHEN BackupType = N'DIFFERENTIAL' THEN BackupFinishAtSource END) AS LastDifferentialBackupAtSource,
               MAX(CASE WHEN BackupType = N'LOG' THEN BackupFinishAtSource END) AS LastLogBackupAtSource
        FROM LatestBackup WHERE rn = 1
    )
    SELECT d.Id AS DatabaseId, d.DatabaseName, s.Id AS ServerId, s.ServerName, d.DatabaseStatus, d.RecoveryModel, d.LastSeenAtUtc,
           c.CurrentDataSizeMb, c.CurrentLogSizeMb, c.CurrentTotalSizeMb,
           b.LastFullBackupAtSource, b.LastDifferentialBackupAtSource, b.LastLogBackupAtSource
    FROM dbo.Databases AS d INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
    CROSS JOIN Capacity AS c CROSS JOIN BackupAgg AS b
    WHERE d.Id = @DatabaseId
    GROUP BY d.Id, d.DatabaseName, s.Id, s.ServerName, d.DatabaseStatus, d.RecoveryModel, d.LastSeenAtUtc,
             c.CurrentDataSizeMb, c.CurrentLogSizeMb, c.CurrentTotalSizeMb,
             b.LastFullBackupAtSource, b.LastDifferentialBackupAtSource, b.LastLogBackupAtSource;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Database_CapacityHistory
    @DatabaseId int,
    @Days int = 30
AS
BEGIN
    SET NOCOUNT ON;
    SET @Days = CASE WHEN @Days IN (7, 30, 90, 180, 365) THEN @Days ELSE 30 END;
    SELECT MAX(CollectedAtUtc) AS CollectedAtUtc,
           SUM(CASE WHEN FileType = N'ROWS' THEN AllocatedSizeMb ELSE 0 END) AS DataSizeMb,
           SUM(CASE WHEN FileType = N'LOG' THEN AllocatedSizeMb ELSE 0 END) AS LogSizeMb,
           SUM(AllocatedSizeMb) AS TotalSizeMb
    FROM dbo.CapacitySnapshots
    WHERE DatabaseId = @DatabaseId AND CollectedAtUtc >= DATEADD(DAY, -@Days, SYSUTCDATETIME())
    GROUP BY CollectionRunId
    ORDER BY CollectedAtUtc ASC;
END;
GO
