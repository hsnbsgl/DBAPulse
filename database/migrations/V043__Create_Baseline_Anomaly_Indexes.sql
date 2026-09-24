CREATE INDEX IX_Baselines_MetricScope ON dbo.Baselines (MetricType, ServerId, DatabaseId, EntityKey, BaselineScope, CalculatedAtUtc DESC);
CREATE INDEX IX_Baselines_StatusCalculated ON dbo.Baselines (Status, CalculatedAtUtc DESC);
CREATE INDEX IX_AnomalyFindings_StatusSeverityObserved ON dbo.AnomalyFindings (Status, Severity, ObservedAtUtc DESC);
CREATE INDEX IX_AnomalyFindings_MetricEntityObserved ON dbo.AnomalyFindings (MetricType, ServerId, DatabaseId, EntityKey, ObservedAtUtc DESC);
CREATE UNIQUE INDEX UX_AnomalyFindings_ActiveFingerprint ON dbo.AnomalyFindings (Fingerprint) WHERE Status = N'Active';
