CREATE UNIQUE INDEX UX_OperationalEvents_Active_Fingerprint ON dbo.OperationalEvents (EventType, Fingerprint) WHERE Status = N'Active';
CREATE UNIQUE INDEX UX_OperationalEvents_Deadlock_Fingerprint ON dbo.OperationalEvents (Fingerprint) WHERE EventType = N'Deadlock';
CREATE INDEX IX_OperationalEvents_Status_LastSeen ON dbo.OperationalEvents (Status, LastSeenAtUtc DESC);
CREATE INDEX IX_OperationalEvents_Type_Started ON dbo.OperationalEvents (EventType, StartedAtUtc DESC);
CREATE INDEX IX_OperationalEvents_Server_Started ON dbo.OperationalEvents (ServerId, StartedAtUtc DESC);
CREATE INDEX IX_OperationalEvents_Database_Started ON dbo.OperationalEvents (DatabaseId, StartedAtUtc DESC);
