CREATE UNIQUE INDEX UX_Servers_ServerName ON dbo.Servers(ServerName);
CREATE INDEX IX_Servers_LastSeenAtUtc ON dbo.Servers(LastSeenAtUtc);
CREATE INDEX IX_Databases_ServerId_LastSeenAtUtc ON dbo.Databases(ServerId, LastSeenAtUtc);

CREATE INDEX IX_ServerSnapshots_Server_CollectedAtUtc ON dbo.ServerSnapshots(ServerId, CollectedAtUtc);
CREATE INDEX IX_DatabaseSnapshots_Database_CollectedAtUtc ON dbo.DatabaseSnapshots(DatabaseId, CollectedAtUtc);
CREATE INDEX IX_BackupSnapshots_Server_CollectedAtUtc ON dbo.BackupSnapshots(ServerId, CollectedAtUtc);
CREATE INDEX IX_BackupSnapshots_Database_CollectedAtUtc ON dbo.BackupSnapshots(DatabaseId, CollectedAtUtc);
CREATE INDEX IX_JobSnapshots_Server_CollectedAtUtc ON dbo.JobSnapshots(ServerId, CollectedAtUtc);
CREATE INDEX IX_AlwaysOnSnapshots_Server_CollectedAtUtc ON dbo.AlwaysOnSnapshots(ServerId, CollectedAtUtc);
CREATE INDEX IX_CapacitySnapshots_Database_CollectedAtUtc ON dbo.CapacitySnapshots(DatabaseId, CollectedAtUtc);
CREATE INDEX IX_CollectionErrors_Run_CreatedAtUtc ON dbo.CollectionErrors(CollectionRunId, CreatedAtUtc);

ALTER TABLE dbo.ServerSnapshots ADD CONSTRAINT FK_ServerSnapshots_Runs FOREIGN KEY (CollectionRunId) REFERENCES dbo.CollectionRuns(Id);
ALTER TABLE dbo.ServerSnapshots ADD CONSTRAINT FK_ServerSnapshots_Servers FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id);
ALTER TABLE dbo.DatabaseSnapshots ADD CONSTRAINT FK_DatabaseSnapshots_Runs FOREIGN KEY (CollectionRunId) REFERENCES dbo.CollectionRuns(Id);
ALTER TABLE dbo.DatabaseSnapshots ADD CONSTRAINT FK_DatabaseSnapshots_Databases FOREIGN KEY (DatabaseId) REFERENCES dbo.Databases(Id);
ALTER TABLE dbo.BackupSnapshots ADD CONSTRAINT FK_BackupSnapshots_Runs FOREIGN KEY (CollectionRunId) REFERENCES dbo.CollectionRuns(Id);
ALTER TABLE dbo.BackupSnapshots ADD CONSTRAINT FK_BackupSnapshots_Servers FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id);
ALTER TABLE dbo.BackupSnapshots ADD CONSTRAINT FK_BackupSnapshots_Databases FOREIGN KEY (DatabaseId) REFERENCES dbo.Databases(Id);
ALTER TABLE dbo.JobSnapshots ADD CONSTRAINT FK_JobSnapshots_Runs FOREIGN KEY (CollectionRunId) REFERENCES dbo.CollectionRuns(Id);
ALTER TABLE dbo.JobSnapshots ADD CONSTRAINT FK_JobSnapshots_Servers FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id);
ALTER TABLE dbo.AlwaysOnSnapshots ADD CONSTRAINT FK_AlwaysOnSnapshots_Runs FOREIGN KEY (CollectionRunId) REFERENCES dbo.CollectionRuns(Id);
ALTER TABLE dbo.AlwaysOnSnapshots ADD CONSTRAINT FK_AlwaysOnSnapshots_Servers FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id);
ALTER TABLE dbo.CapacitySnapshots ADD CONSTRAINT FK_CapacitySnapshots_Runs FOREIGN KEY (CollectionRunId) REFERENCES dbo.CollectionRuns(Id);
ALTER TABLE dbo.CapacitySnapshots ADD CONSTRAINT FK_CapacitySnapshots_Servers FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id);
ALTER TABLE dbo.CapacitySnapshots ADD CONSTRAINT FK_CapacitySnapshots_Databases FOREIGN KEY (DatabaseId) REFERENCES dbo.Databases(Id);
GO
