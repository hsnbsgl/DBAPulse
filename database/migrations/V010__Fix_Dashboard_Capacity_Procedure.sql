CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_Capacity
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH Latest AS
    (
        SELECT c.*, ROW_NUMBER() OVER (PARTITION BY c.DatabaseId, c.FileType ORDER BY c.CollectedAtUtc DESC, c.Id DESC) AS rn
        FROM dbo.CapacitySnapshots AS c
    )
    SELECT
        COALESCE(SUM(CASE WHEN FileType = N'ROWS' THEN AllocatedSizeMb ELSE 0 END), 0) AS TotalDataSizeMb,
        COALESCE(SUM(CASE WHEN FileType = N'LOG' THEN AllocatedSizeMb ELSE 0 END), 0) AS TotalLogSizeMb,
        COALESCE(SUM(AllocatedSizeMb), 0) AS TotalDatabaseSizeMb
    FROM Latest WHERE rn = 1;

    ;WITH Latest AS
    (
        SELECT c.*, ROW_NUMBER() OVER (PARTITION BY c.DatabaseId, c.FileType ORDER BY c.CollectedAtUtc DESC, c.Id DESC) AS rn
        FROM dbo.CapacitySnapshots AS c
    )
    SELECT DatabaseId, DatabaseName, ServerId,
           SUM(CASE WHEN FileType = N'ROWS' THEN AllocatedSizeMb ELSE 0 END) AS DataSizeMb,
           SUM(CASE WHEN FileType = N'LOG' THEN AllocatedSizeMb ELSE 0 END) AS LogSizeMb,
           SUM(AllocatedSizeMb) AS TotalSizeMb,
           MAX(CollectedAtUtc) AS CollectedAtUtc
    FROM Latest WHERE rn = 1
    GROUP BY DatabaseId, DatabaseName, ServerId
    ORDER BY DatabaseName;
END;
GO
