CREATE INDEX IX_AuditLogs_OccurredAtUtc ON dbo.AuditLogs(OccurredAtUtc DESC, Id DESC);
CREATE INDEX IX_AuditLogs_UserName_OccurredAtUtc ON dbo.AuditLogs(UserName, OccurredAtUtc DESC, Id DESC);
CREATE INDEX IX_AuditLogs_Action_OccurredAtUtc ON dbo.AuditLogs(Action, OccurredAtUtc DESC, Id DESC);
CREATE INDEX IX_AuditLogs_CorrelationId ON dbo.AuditLogs(CorrelationId, OccurredAtUtc DESC);
