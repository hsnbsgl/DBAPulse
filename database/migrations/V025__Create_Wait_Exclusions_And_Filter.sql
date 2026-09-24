INSERT dbo.WaitTypeExclusions (WaitType, Reason, IsEnabled)
SELECT v.WaitType, v.Reason, 1 FROM (VALUES
 (N'QDS_ASYNC_QUEUE', N'Query Store background worker'),
 (N'SOS_WORK_DISPATCHER', N'Internal dispatcher background wait'),
 (N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'Internal HADR/FileStream background wait')) v(WaitType, Reason)
WHERE NOT EXISTS (SELECT 1 FROM dbo.WaitTypeExclusions e WHERE e.WaitType = v.WaitType);
GO

CREATE OR ALTER PROCEDURE dbo.usp_WaitStats_Top
    @Hours int = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET @Hours = CASE WHEN @Hours IN (1, 6, 12, 24, 48, 168) THEN @Hours ELSE 24 END;
    ;WITH History AS
    (
        SELECT w.*, LAG(w.WaitTimeMs) OVER (PARTITION BY w.ServerId, w.WaitType, w.SqlServerStartTimeUtc ORDER BY w.CapturedAtUtc, w.Id) AS PreviousWaitTimeMs,
               LAG(w.SignalWaitTimeMs) OVER (PARTITION BY w.ServerId, w.WaitType, w.SqlServerStartTimeUtc ORDER BY w.CapturedAtUtc, w.Id) AS PreviousSignalWaitTimeMs,
               LAG(w.WaitingTasksCount) OVER (PARTITION BY w.ServerId, w.WaitType, w.SqlServerStartTimeUtc ORDER BY w.CapturedAtUtc, w.Id) AS PreviousWaitingTasksCount
        FROM dbo.WaitStatsSnapshots AS w
    ), Delta AS
    (
        SELECT h.WaitType, SUM(h.WaitTimeMs - h.PreviousWaitTimeMs) AS WaitTimeDeltaMs,
               SUM(h.SignalWaitTimeMs - h.PreviousSignalWaitTimeMs) AS SignalWaitDeltaMs,
               SUM(h.WaitingTasksCount - h.PreviousWaitingTasksCount) AS WaitingTasksDelta
        FROM History h LEFT JOIN dbo.WaitTypeExclusions x ON x.WaitType = h.WaitType AND x.IsEnabled = 1
        WHERE h.CapturedAtUtc >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME()) AND h.PreviousWaitTimeMs IS NOT NULL
          AND h.WaitTimeMs >= h.PreviousWaitTimeMs AND h.SignalWaitTimeMs >= h.PreviousSignalWaitTimeMs AND h.WaitingTasksCount >= h.PreviousWaitingTasksCount
          AND x.WaitType IS NULL
        GROUP BY h.WaitType
    )
    SELECT WaitType, WaitTimeDeltaMs, SignalWaitDeltaMs, WaitingTasksDelta,
           CONVERT(decimal(9,2), 100.0 * WaitTimeDeltaMs / NULLIF(SUM(WaitTimeDeltaMs) OVER (), 0)) AS Percentage
    FROM Delta WHERE WaitTimeDeltaMs > 0 ORDER BY WaitTimeDeltaMs DESC;
END;
