CREATE OR ALTER PROCEDURE dbo.usp_AnomalySamples_List
    @FromUtc datetime2(3),
    @ToUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT N'BlockingDuration', ServerId, DatabaseId, CAST(NULL AS nvarchar(256)), CapturedAtUtc, CONVERT(decimal(28,6), WaitDurationMs), Id
    FROM dbo.BlockingEvents WHERE CapturedAtUtc BETWEEN @FromUtc AND @ToUtc
    UNION ALL
    SELECT N'BlockingFrequency', ServerId, DatabaseId, CAST(NULL AS nvarchar(256)), BucketUtc, CONVERT(decimal(28,6), COUNT_BIG(*)), MAX(Id)
    FROM (SELECT ServerId, DatabaseId, DATEADD(hour, DATEDIFF(hour, 0, CapturedAtUtc), 0) BucketUtc, Id FROM dbo.BlockingEvents WHERE CapturedAtUtc BETWEEN @FromUtc AND @ToUtc) b
    GROUP BY ServerId, DatabaseId, BucketUtc
    UNION ALL
    SELECT N'LongRunningDuration', ServerId, DatabaseId, SqlTextHash, CapturedAtUtc, CONVERT(decimal(28,6), ElapsedMs), Id
    FROM dbo.LongRunningRequestSnapshots WHERE CapturedAtUtc BETWEEN @FromUtc AND @ToUtc
    UNION ALL
    SELECT N'JobDuration', ServerId, NULL, JobId, CollectedAtUtc, CONVERT(decimal(28,6), LastRunDurationSeconds), Id
    FROM dbo.JobSnapshots WHERE CollectedAtUtc BETWEEN @FromUtc AND @ToUtc AND LastRunStatus = N'Succeeded' AND LastRunDurationSeconds IS NOT NULL
    UNION ALL
    SELECT N'BackupDuration', ServerId, DatabaseId, BackupType, CollectedAtUtc, CONVERT(decimal(28,6), BackupDurationSeconds), Id
    FROM dbo.BackupSnapshots WHERE CollectedAtUtc BETWEEN @FromUtc AND @ToUtc AND BackupDurationSeconds IS NOT NULL
    UNION ALL
    SELECT N'DatabaseGrowth', ServerId, DatabaseId, CAST(NULL AS nvarchar(256)), CollectedAtUtc, GrowthValue, Id
    FROM (
        SELECT ServerId, DatabaseId, CollectedAtUtc, Id,
               AllocatedSizeMb - LAG(AllocatedSizeMb) OVER (PARTITION BY ServerId, DatabaseId, FileType ORDER BY CollectedAtUtc) GrowthValue
        FROM dbo.CapacitySnapshots
        WHERE CollectedAtUtc BETWEEN DATEADD(day, -1, @FromUtc) AND @ToUtc
    ) growth
    WHERE GrowthValue IS NOT NULL
    UNION ALL
    SELECT N'WaitDelta', waits.ServerId, NULL, waits.WaitType, waits.CapturedAtUtc, waits.WaitDeltaMs, waits.Id
    FROM (
        SELECT ServerId, WaitType, CapturedAtUtc, Id,
               WaitTimeMs - LAG(WaitTimeMs) OVER (PARTITION BY ServerId, WaitType, SqlServerStartTimeUtc ORDER BY CapturedAtUtc) WaitDeltaMs
        FROM dbo.WaitStatsSnapshots
        WHERE CapturedAtUtc BETWEEN @FromUtc AND @ToUtc
    ) waits
    LEFT JOIN dbo.WaitTypeExclusions exclusions ON exclusions.WaitType = waits.WaitType AND exclusions.IsEnabled = 1
    WHERE waits.WaitDeltaMs > 0 AND exclusions.WaitType IS NULL;
END;
GO
