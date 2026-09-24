CREATE OR ALTER PROCEDURE dbo.usp_BlockingEvents_Insert
    @Rows dbo.BlockingEventInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.BlockingEvents (ServerId, DatabaseId, CapturedAtUtc, SessionId, BlockingSessionId, WaitType, WaitDurationMs, Command, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview)
    SELECT ServerId, DatabaseId, CapturedAtUtc, SessionId, BlockingSessionId, WaitType, WaitDurationMs, Command, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LongRunningRequests_Insert
    @Rows dbo.LongRunningRequestInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.LongRunningRequestSnapshots (ServerId, DatabaseId, CapturedAtUtc, SessionId, RequestStartTimeUtc, ElapsedMs, Status, Command, WaitType, WaitTimeMs, CpuTimeMs, LogicalReads, Reads, Writes, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview)
    SELECT ServerId, DatabaseId, CapturedAtUtc, SessionId, RequestStartTimeUtc, ElapsedMs, Status, Command, WaitType, WaitTimeMs, CpuTimeMs, LogicalReads, Reads, Writes, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_WaitStatsSnapshots_Insert
    @Rows dbo.WaitStatsSnapshotInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.WaitStatsSnapshots (ServerId, CapturedAtUtc, SqlServerStartTimeUtc, WaitType, WaitTimeMs, SignalWaitTimeMs, WaitingTasksCount)
    SELECT ServerId, CapturedAtUtc, SqlServerStartTimeUtc, WaitType, WaitTimeMs, SignalWaitTimeMs, WaitingTasksCount FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DeadlockEvents_Insert
    @Rows dbo.DeadlockEventInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.DeadlockEvents (ServerId, DatabaseId, OccurredAtUtc, VictimProcessId, VictimSessionId, ProcessCount, DeadlockHash, DeadlockXml, CollectedAtUtc)
    SELECT r.ServerId, r.DatabaseId, r.OccurredAtUtc, r.VictimProcessId, r.VictimSessionId, r.ProcessCount, r.DeadlockHash, r.DeadlockXml, r.CollectedAtUtc
    FROM @Rows AS r
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DeadlockEvents AS d WHERE d.DeadlockHash = r.DeadlockHash);
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
