CREATE OR ALTER PROCEDURE dbo.usp_Performance_Overview
    @Hours int = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET @Hours = CASE WHEN @Hours IN (1, 6, 12, 24, 48, 168) THEN @Hours ELSE 24 END;
    DECLARE @Since datetime2(3) = DATEADD(HOUR, -@Hours, SYSUTCDATETIME());
    SELECT
        (SELECT COUNT_BIG(*) FROM dbo.BlockingEvents WHERE CapturedAtUtc >= @Since) AS BlockingObservationCount,
        COALESCE((SELECT MAX(WaitDurationMs) FROM dbo.BlockingEvents WHERE CapturedAtUtc >= @Since), 0) AS MaxBlockingDurationMs,
        (SELECT COUNT_BIG(*) FROM dbo.DeadlockEvents WHERE OccurredAtUtc >= @Since) AS DeadlockCount,
        (SELECT COUNT_BIG(*) FROM dbo.LongRunningRequestSnapshots WHERE CapturedAtUtc >= @Since) AS LongRunningObservationCount,
        (SELECT MAX(CapturedAtUtc) FROM dbo.WaitStatsSnapshots) AS LastPerformanceCollectionAtUtc;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Blocking_Recent
    @Hours int = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET @Hours = CASE WHEN @Hours IN (1, 6, 12, 24, 48, 168) THEN @Hours ELSE 24 END;
    SELECT TOP (200) b.Id, b.CapturedAtUtc, s.ServerName, d.DatabaseName, b.SessionId, b.BlockingSessionId,
           b.WaitType, b.WaitDurationMs, b.Command, b.HostName, b.ApplicationName, b.LoginName, b.SqlTextHash, b.SqlTextPreview
    FROM dbo.BlockingEvents AS b
    INNER JOIN dbo.Servers AS s ON s.Id = b.ServerId
    LEFT JOIN dbo.Databases AS d ON d.Id = b.DatabaseId
    WHERE b.CapturedAtUtc >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
    ORDER BY b.CapturedAtUtc DESC, b.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Deadlocks_Recent
    @Hours int = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET @Hours = CASE WHEN @Hours IN (1, 6, 12, 24, 48, 168) THEN @Hours ELSE 24 END;
    SELECT TOP (200) d.Id, d.OccurredAtUtc, d.CollectedAtUtc, s.ServerName, db.DatabaseName,
           d.VictimProcessId, d.VictimSessionId, d.ProcessCount, d.DeadlockHash
    FROM dbo.DeadlockEvents AS d
    INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
    LEFT JOIN dbo.Databases AS db ON db.Id = d.DatabaseId
    WHERE d.OccurredAtUtc >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
    ORDER BY d.OccurredAtUtc DESC, d.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LongRunning_Recent
    @Hours int = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET @Hours = CASE WHEN @Hours IN (1, 6, 12, 24, 48, 168) THEN @Hours ELSE 24 END;
    SELECT TOP (200) r.Id, r.CapturedAtUtc, s.ServerName, d.DatabaseName, r.SessionId, r.ElapsedMs,
           r.Status, r.Command, r.WaitType, r.WaitTimeMs, r.CpuTimeMs, r.LogicalReads, r.Reads, r.Writes,
           r.HostName, r.ApplicationName, r.LoginName, r.SqlTextHash, r.SqlTextPreview
    FROM dbo.LongRunningRequestSnapshots AS r
    INNER JOIN dbo.Servers AS s ON s.Id = r.ServerId
    LEFT JOIN dbo.Databases AS d ON d.Id = r.DatabaseId
    WHERE r.CapturedAtUtc >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
    ORDER BY r.CapturedAtUtc DESC, r.ElapsedMs DESC;
END;
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
        SELECT WaitType, SUM(WaitTimeMs - PreviousWaitTimeMs) AS WaitTimeDeltaMs,
               SUM(SignalWaitTimeMs - PreviousSignalWaitTimeMs) AS SignalWaitDeltaMs,
               SUM(WaitingTasksCount - PreviousWaitingTasksCount) AS WaitingTasksDelta
        FROM History
        WHERE CapturedAtUtc >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
          AND PreviousWaitTimeMs IS NOT NULL
          AND WaitTimeMs >= PreviousWaitTimeMs
          AND SignalWaitTimeMs >= PreviousSignalWaitTimeMs
          AND WaitingTasksCount >= PreviousWaitingTasksCount
        GROUP BY WaitType
    ), Positive AS
    (
        SELECT * FROM Delta WHERE WaitTimeDeltaMs > 0
    )
    SELECT WaitType, WaitTimeDeltaMs, SignalWaitDeltaMs, WaitingTasksDelta,
           CONVERT(decimal(9,2), 100.0 * WaitTimeDeltaMs / NULLIF(SUM(WaitTimeDeltaMs) OVER (), 0)) AS Percentage
    FROM Positive ORDER BY WaitTimeDeltaMs DESC;
END;
