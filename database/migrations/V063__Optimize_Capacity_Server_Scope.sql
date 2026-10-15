/* Capacity reads are server-scoped in the UI. Keep the server and current-row
   keys together so SQL Server can discard unrelated snapshots before grouping. */

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CapacitySnapshots_ServerDatabaseCurrent' AND object_id = OBJECT_ID(N'dbo.CapacitySnapshots'))
    CREATE INDEX IX_CapacitySnapshots_ServerDatabaseCurrent
        ON dbo.CapacitySnapshots(ServerId, DatabaseId, FileType, CollectedAtUtc DESC, Id DESC)
        INCLUDE (DatabaseName, AllocatedSizeMb);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CapacitySnapshots_DatabaseHistory' AND object_id = OBJECT_ID(N'dbo.CapacitySnapshots'))
    CREATE INDEX IX_CapacitySnapshots_DatabaseHistory
        ON dbo.CapacitySnapshots(DatabaseId, CollectedAtUtc DESC, Id DESC)
        INCLUDE (FileType, AllocatedSizeMb);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_VolumeCapacitySnapshots_ServerCurrent' AND object_id = OBJECT_ID(N'dbo.VolumeCapacitySnapshots'))
    CREATE INDEX IX_VolumeCapacitySnapshots_ServerCurrent
        ON dbo.VolumeCapacitySnapshots(ServerId, VolumeId, CollectedAtUtc DESC, Id DESC)
        INCLUDE (TotalBytes, AvailableBytes);
GO

CREATE OR ALTER PROCEDURE dbo.usp_Capacity_Databases
    @Status nvarchar(30)=NULL,
    @ServerId int=NULL,
    @ForecastStatus nvarchar(30)=NULL,
    @PageNumber int=1,
    @PageSize int=50,
    @DatabaseId int=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
    SET @PageNumber=CASE WHEN @PageNumber<1 THEN 1 ELSE @PageNumber END;

    ;WITH ScopedDatabases AS
    (
        SELECT d.Id AS DatabaseId,d.DatabaseName,d.ServerId,s.ServerName
        FROM dbo.Databases d
        JOIN dbo.Servers s ON s.Id=d.ServerId AND s.IsActive=1
        WHERE d.IsActive=1
          AND (@ServerId IS NULL OR d.ServerId=@ServerId)
          AND (@DatabaseId IS NULL OR d.Id=@DatabaseId)
    ), SnapshotByTime AS
    (
        SELECT c.DatabaseId,c.CollectedAtUtc,
               SUM(CASE WHEN c.FileType LIKE N'%LOG%' THEN 0 ELSE c.AllocatedSizeMb END) AS DataMb,
               SUM(CASE WHEN c.FileType LIKE N'%LOG%' THEN c.AllocatedSizeMb ELSE 0 END) AS LogMb
        FROM dbo.CapacitySnapshots c
        JOIN ScopedDatabases d ON d.DatabaseId=c.DatabaseId
        GROUP BY c.DatabaseId,c.CollectedAtUtc
    ), Daily AS
    (
        SELECT x.*,CAST(x.CollectedAtUtc AS date) AS DayValue,
               ROW_NUMBER() OVER(PARTITION BY x.DatabaseId,CAST(x.CollectedAtUtc AS date) ORDER BY x.CollectedAtUtc DESC) AS DayRank
        FROM SnapshotByTime x
    ), CurrentRows AS
    (
        SELECT *,ROW_NUMBER() OVER(PARTITION BY DatabaseId ORDER BY CollectedAtUtc DESC) AS CurrentRank
        FROM Daily WHERE DayRank=1
    ), Metrics AS
    (
        SELECT c.DatabaseId,c.DataMb,c.LogMb,c.DataMb+c.LogMb AS TotalMb,c.CollectedAtUtc,
               COUNT(s.DayValue) AS SampleCount,DATEDIFF(DAY,MIN(s.DayValue),MAX(s.DayValue)) AS HistoryDays
        FROM CurrentRows c
        JOIN Daily s ON s.DatabaseId=c.DatabaseId
        WHERE c.CurrentRank=1
        GROUP BY c.DatabaseId,c.DataMb,c.LogMb,c.CollectedAtUtc
    ), Refs AS
    (
        SELECT m.*,r7.TotalMb AS Ref7,r30.TotalMb AS Ref30,r90.TotalMb AS Ref90
        FROM Metrics m
        OUTER APPLY(SELECT TOP(1) DataMb+LogMb AS TotalMb FROM Daily WHERE DatabaseId=m.DatabaseId AND DayValue<=DATEADD(DAY,-7,CAST(m.CollectedAtUtc AS date)) ORDER BY DayValue DESC) r7
        OUTER APPLY(SELECT TOP(1) DataMb+LogMb AS TotalMb FROM Daily WHERE DatabaseId=m.DatabaseId AND DayValue<=DATEADD(DAY,-30,CAST(m.CollectedAtUtc AS date)) ORDER BY DayValue DESC) r30
        OUTER APPLY(SELECT TOP(1) DataMb+LogMb AS TotalMb FROM Daily WHERE DatabaseId=m.DatabaseId AND DayValue<=DATEADD(DAY,-90,CAST(m.CollectedAtUtc AS date)) ORDER BY DayValue DESC) r90
    )
    SELECT d.DatabaseId,d.DatabaseName,d.ServerName,r.DataMb AS CurrentDataSizeMb,r.LogMb AS CurrentLogSizeMb,r.TotalMb AS CurrentTotalSizeMb,
           CASE WHEN r.Ref7 IS NULL THEN NULL ELSE r.TotalMb-r.Ref7 END AS Growth7dMb,
           CASE WHEN r.Ref30 IS NULL THEN NULL ELSE r.TotalMb-r.Ref30 END AS Growth30dMb,
           CASE WHEN r.Ref90 IS NULL THEN NULL ELSE r.TotalMb-r.Ref90 END AS Growth90dMb,
           CAST(NULL AS decimal(19,4)) AS GrowthRateMbPerDay,CAST(NULL AS decimal(19,2)) AS Forecast30dMb,
           CAST(NULL AS decimal(19,2)) AS Forecast90dMb,CAST(NULL AS decimal(19,6)) AS RSquared,
           r.SampleCount,r.HistoryDays,
           CASE WHEN r.SampleCount<7 OR r.HistoryDays<7 THEN N'InsufficientData' ELSE N'Usable' END AS ForecastStatus,
           CASE WHEN r.SampleCount<7 OR r.HistoryDays<7 THEN N'InsufficientData' ELSE N'Healthy' END AS CapacityStatus,
           r.CollectedAtUtc AS LastCollectedAtUtc,
           CASE WHEN r.CollectedAtUtc<DATEADD(HOUR,-3,SYSUTCDATETIME()) THEN N'Stale' ELSE N'Fresh' END AS DataFreshness
    FROM Refs r JOIN ScopedDatabases d ON d.DatabaseId=r.DatabaseId
    WHERE (@ForecastStatus IS NULL OR @ForecastStatus=(CASE WHEN r.SampleCount<7 OR r.HistoryDays<7 THEN N'InsufficientData' ELSE N'Usable' END))
    ORDER BY d.DatabaseName
    OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount
    FROM dbo.Databases d
    JOIN dbo.Servers s ON s.Id=d.ServerId AND s.IsActive=1
    WHERE d.IsActive=1
      AND (@ServerId IS NULL OR d.ServerId=@ServerId)
      AND (@DatabaseId IS NULL OR d.Id=@DatabaseId);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Capacity_DatabaseHistory
    @DatabaseId int,
    @Days int=30
AS
BEGIN
    SET NOCOUNT ON;
    SET @Days=CASE WHEN @Days IN(7,30,90,180,365) THEN @Days ELSE 30 END;
    ;WITH x AS
    (
        SELECT c.CollectedAtUtc,
               SUM(CASE WHEN c.FileType LIKE N'%LOG%' THEN 0 ELSE c.AllocatedSizeMb END) AS DataMb,
               SUM(CASE WHEN c.FileType LIKE N'%LOG%' THEN c.AllocatedSizeMb ELSE 0 END) AS LogMb
        FROM dbo.CapacitySnapshots c
        WHERE c.DatabaseId=@DatabaseId
          AND c.CollectedAtUtc>=DATEADD(DAY,-@Days,SYSUTCDATETIME())
        GROUP BY c.CollectedAtUtc
    )
    SELECT CollectedAtUtc,DataMb AS DataSizeMb,LogMb AS LogSizeMb,DataMb+LogMb AS TotalSizeMb,
           CAST(NULL AS decimal(19,2)) AS ForecastTotalSizeMb,N'Actual' AS SeriesType
    FROM x ORDER BY CollectedAtUtc;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Capacity_Volumes
    @Status nvarchar(30)=NULL,
    @ServerId int=NULL,
    @ForecastStatus nvarchar(30)=NULL,
    @PageNumber int=1,
    @PageSize int=50,
    @VolumeId nvarchar(512)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
    SET @PageNumber=CASE WHEN @PageNumber<1 THEN 1 ELSE @PageNumber END;

    ;WITH Latest AS
    (
        SELECT v.*,ROW_NUMBER() OVER(PARTITION BY v.ServerId,v.VolumeId ORDER BY v.CollectedAtUtc DESC,v.Id DESC) AS rn
        FROM dbo.VolumeCapacitySnapshots v
        JOIN dbo.Servers s ON s.Id=v.ServerId AND s.IsActive=1
        WHERE (@ServerId IS NULL OR v.ServerId=@ServerId)
          AND (@VolumeId IS NULL OR v.VolumeId=@VolumeId)
    )
    SELECT v.Id,v.ServerId,s.ServerName,v.VolumeId,v.TotalBytes,v.AvailableBytes,
           CAST(v.AvailableBytes*100.0/NULLIF(v.TotalBytes,0) AS decimal(9,2)) AS FreePercent,
           CAST(NULL AS decimal(19,2)) AS GrowthBytesPerDay,CAST(NULL AS decimal(19,2)) AS EstimatedExhaustionDays,
           N'InsufficientData' AS ForecastStatus,
           CASE WHEN v.AvailableBytes*100.0/NULLIF(v.TotalBytes,0)<=10 THEN N'Critical'
                WHEN v.AvailableBytes*100.0/NULLIF(v.TotalBytes,0)<=15 THEN N'Warning' ELSE N'Healthy' END AS CapacityStatus,
           1 AS SampleCount,v.CollectedAtUtc,
           CASE WHEN v.CollectedAtUtc<DATEADD(HOUR,-3,SYSUTCDATETIME()) THEN N'Stale' ELSE N'Fresh' END AS DataFreshness
    FROM Latest v JOIN dbo.Servers s ON s.Id=v.ServerId
    WHERE v.rn=1
    ORDER BY v.VolumeId
    OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    ;WITH Latest AS
    (
        SELECT v.ServerId,v.VolumeId,ROW_NUMBER() OVER(PARTITION BY v.ServerId,v.VolumeId ORDER BY v.CollectedAtUtc DESC,v.Id DESC) AS rn
        FROM dbo.VolumeCapacitySnapshots v
        JOIN dbo.Servers s ON s.Id=v.ServerId AND s.IsActive=1
        WHERE (@ServerId IS NULL OR v.ServerId=@ServerId)
          AND (@VolumeId IS NULL OR v.VolumeId=@VolumeId)
    )
    SELECT COUNT(*) AS TotalCount FROM Latest WHERE rn=1;
END;
GO
