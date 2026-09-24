CREATE INDEX IX_CollectionRuns_StartedAtUtc ON dbo.CollectionRuns(StartedAtUtc DESC);
CREATE INDEX IX_CollectionErrors_CollectionRunId ON dbo.CollectionErrors(CollectionRunId);
CREATE INDEX IX_BackupSnapshots_CurrentLookup ON dbo.BackupSnapshots(DatabaseId, BackupType, CollectedAtUtc DESC, Id DESC);
CREATE INDEX IX_CapacitySnapshots_CurrentLookup ON dbo.CapacitySnapshots(DatabaseId, FileType, CollectedAtUtc DESC, Id DESC);
