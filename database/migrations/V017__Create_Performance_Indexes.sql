CREATE INDEX IX_BlockingEvents_Server_Captured ON dbo.BlockingEvents (ServerId, CapturedAtUtc DESC);
CREATE INDEX IX_BlockingEvents_Database_Captured ON dbo.BlockingEvents (DatabaseId, CapturedAtUtc DESC);
CREATE INDEX IX_LongRunning_Server_Captured ON dbo.LongRunningRequestSnapshots (ServerId, CapturedAtUtc DESC);
CREATE INDEX IX_LongRunning_Database_Captured ON dbo.LongRunningRequestSnapshots (DatabaseId, CapturedAtUtc DESC);
CREATE INDEX IX_WaitStats_Server_Type_Captured ON dbo.WaitStatsSnapshots (ServerId, WaitType, CapturedAtUtc DESC);
CREATE INDEX IX_Deadlocks_Server_Occurred ON dbo.DeadlockEvents (ServerId, OccurredAtUtc DESC);
CREATE INDEX IX_Deadlocks_Occurred ON dbo.DeadlockEvents (OccurredAtUtc DESC);
