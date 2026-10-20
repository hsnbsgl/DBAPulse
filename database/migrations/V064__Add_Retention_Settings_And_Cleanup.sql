IF COL_LENGTH(N'dbo.Servers', N'RetentionDays') IS NULL
    ALTER TABLE dbo.Servers ADD RetentionDays int NOT NULL CONSTRAINT DF_Servers_RetentionDays DEFAULT (30);
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Servers_RetentionDays')
    ALTER TABLE dbo.Servers ADD CONSTRAINT CK_Servers_RetentionDays CHECK (RetentionDays BETWEEN 1 AND 3650);
GO

IF OBJECT_ID(N'dbo.RetentionSettings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RetentionSettings
    (
        Id tinyint NOT NULL CONSTRAINT PK_RetentionSettings PRIMARY KEY,
        CleanupIntervalHours int NOT NULL CONSTRAINT DF_RetentionSettings_CleanupIntervalHours DEFAULT (24),
        LastCleanupAtUtc datetime2(3) NULL,
        CONSTRAINT CK_RetentionSettings_Id CHECK (Id = 1),
        CONSTRAINT CK_RetentionSettings_CleanupIntervalHours CHECK (CleanupIntervalHours BETWEEN 1 AND 720)
    );
    INSERT dbo.RetentionSettings (Id, CleanupIntervalHours) VALUES (1, 24);
END;
GO

CREATE INDEX IX_ServerSnapshots_ServerCollectedAt ON dbo.ServerSnapshots(ServerId, CollectedAtUtc);
CREATE INDEX IX_DatabaseSnapshots_DatabaseCollectedAt ON dbo.DatabaseSnapshots(DatabaseId, CollectedAtUtc);
CREATE INDEX IX_BackupSnapshots_ServerCollectedAt ON dbo.BackupSnapshots(ServerId, CollectedAtUtc);
CREATE INDEX IX_JobSnapshots_ServerCollectedAt ON dbo.JobSnapshots(ServerId, CollectedAtUtc);
CREATE INDEX IX_AlwaysOnSnapshots_ServerCollectedAt ON dbo.AlwaysOnSnapshots(ServerId, CollectedAtUtc);
CREATE INDEX IX_BlockingEvents_ServerCapturedAt ON dbo.BlockingEvents(ServerId, CapturedAtUtc);
CREATE INDEX IX_LongRunning_ServerCapturedAt ON dbo.LongRunningRequestSnapshots(ServerId, CapturedAtUtc);
CREATE INDEX IX_WaitStats_ServerCapturedAt ON dbo.WaitStatsSnapshots(ServerId, CapturedAtUtc);
CREATE INDEX IX_DeadlockEvents_ServerOccurredAt ON dbo.DeadlockEvents(ServerId, OccurredAtUtc);
CREATE INDEX IX_OperationalEvents_ServerLastSeenAt ON dbo.OperationalEvents(ServerId, LastSeenAtUtc);
CREATE INDEX IX_AnomalyFindings_ServerLastSeenAt ON dbo.AnomalyFindings(ServerId, LastSeenAtUtc);
CREATE INDEX IX_Baselines_ServerCalculatedAt ON dbo.Baselines(ServerId, CalculatedAtUtc);
CREATE INDEX IX_ManagementGroups_ServerLastSeenAt ON dbo.ManagementCorrelationGroups(ServerId, LastSeenAtUtc);
CREATE INDEX IX_ManagementSignals_ServerLastSeenAt ON dbo.ManagementRelatedSignals(ServerId, LastSeenAtUtc);
GO

CREATE OR ALTER PROCEDURE dbo.usp_Retention_Cleanup
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now datetime2(3) = SYSUTCDATETIME(), @interval int, @last datetime2(3), @lockResult int;
    BEGIN TRANSACTION;
    EXEC @lockResult = sp_getapplock @Resource = N'DBAPulse.RetentionCleanup', @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 0;
    IF @lockResult < 0
    BEGIN
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    SELECT @interval=CleanupIntervalHours,@last=LastCleanupAtUtc
    FROM dbo.RetentionSettings WITH (UPDLOCK, HOLDLOCK) WHERE Id=1;
    IF @interval IS NULL SET @interval=24;
    IF @last IS NOT NULL AND @last > DATEADD(HOUR,-@interval,@now)
    BEGIN
        COMMIT TRANSACTION;
        RETURN;
    END;

    DELETE n
    FROM dbo.AlertNotificationDeliveries n
    JOIN dbo.OperationalEvents e ON e.Id=n.OperationalEventId
    JOIN dbo.Servers s ON s.Id=e.ServerId
    WHERE e.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);

    DELETE rs
    FROM dbo.ManagementRelatedSignals rs
    JOIN dbo.Servers s ON s.Id=rs.ServerId
    WHERE rs.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);

    DELETE g
    FROM dbo.ManagementCorrelationGroups g
    JOIN dbo.Servers s ON s.Id=g.ServerId
    WHERE g.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);

    DELETE e
    FROM dbo.OperationalEvents e
    JOIN dbo.Servers s ON s.Id=e.ServerId
    WHERE e.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);

    DELETE a
    FROM dbo.AnomalyFindings a
    JOIN dbo.Servers s ON s.Id=a.ServerId
    WHERE a.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);

    DELETE b
    FROM dbo.Baselines b
    JOIN dbo.Servers s ON s.Id=b.ServerId
    WHERE b.CalculatedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);

    DELETE x FROM dbo.BlockingEvents x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CapturedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.LongRunningRequestSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CapturedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.WaitStatsSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CapturedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.DeadlockEvents x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.OccurredAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.VolumeCapacitySnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.CapacitySnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.BackupSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.JobSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.AlwaysOnSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x FROM dbo.ServerSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);
    DELETE x
    FROM dbo.DatabaseSnapshots x
    JOIN dbo.Databases d ON d.Id=x.DatabaseId
    JOIN dbo.Servers s ON s.Id=d.ServerId
    WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);

    DELETE e
    FROM dbo.CollectionErrors e
    JOIN dbo.Servers s ON s.ServerName=e.ServerName
    WHERE e.CreatedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);

    UPDATE dbo.RetentionSettings SET LastCleanupAtUtc=@now WHERE Id=1;
    COMMIT TRANSACTION;
END;
GO
