IF COL_LENGTH('dbo.Servers', 'AlertEventTypes') IS NULL
BEGIN
    ALTER TABLE dbo.Servers ADD AlertEventTypes nvarchar(1000) NULL;
END
GO

IF COL_LENGTH('dbo.Servers', 'AlertSeverities') IS NULL
BEGIN
    ALTER TABLE dbo.Servers ADD AlertSeverities nvarchar(100) NULL;
END
GO

UPDATE dbo.Servers
SET AlertEventTypes = COALESCE(NULLIF(AlertEventTypes, N''), N'Blocking,LongRunning,Deadlock,BackupProtection,JobFailure,AlwaysOnHealth,PerformanceAnomaly,GrowthAnomaly'),
    AlertSeverities = COALESCE(NULLIF(AlertSeverities, N''), N'Warning,Critical');
GO
