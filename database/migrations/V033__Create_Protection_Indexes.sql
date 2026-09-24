CREATE INDEX IX_BackupSnapshots_DatabaseTypeCollected ON dbo.BackupSnapshots(DatabaseId, BackupType, CollectedAtUtc DESC) INCLUDE (BackupFinishAtSource, BackupDurationSeconds);
CREATE INDEX IX_AlwaysOnSnapshots_ServerCollected ON dbo.AlwaysOnSnapshots(ServerId, CollectedAtUtc DESC) INCLUDE (AvailabilityGroupName, ReplicaServerName, SynchronizationHealth, SynchronizationState);
CREATE INDEX IX_JobSnapshots_ServerJobCollected ON dbo.JobSnapshots(ServerId, JobId, CollectedAtUtc DESC) INCLUDE (LastRunStatus, IsRunning, RepeatedFailure);
