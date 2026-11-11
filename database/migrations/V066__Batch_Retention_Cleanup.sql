IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_CollectionErrors_CreatedAtUtc' AND object_id = OBJECT_ID(N'dbo.CollectionErrors'))
    CREATE INDEX IX_CollectionErrors_CreatedAtUtc ON dbo.CollectionErrors(CreatedAtUtc) INCLUDE (ServerName, CollectionRunId);
GO

/*
  Same contract as V064 (no parameters, interval gate, single-runner applock), but:
  - deletes run in batches of @batch rows; each DELETE is its own short autocommit transaction,
  - the applock is session-owned so it serializes runners without holding one long transaction,
  - children are deleted before parents (FKs), CollectionRuns are trimmed last,
  - LastCleanupAtUtc is only updated after every step has completed.
*/
CREATE OR ALTER PROCEDURE dbo.usp_Retention_Cleanup
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now datetime2(3) = SYSUTCDATETIME(), @interval int, @last datetime2(3), @lockResult int,
            @batch int = 5000, @rows int, @maxRetentionDays int, @step int, @sql nvarchar(max);

    EXEC @lockResult = sp_getapplock @Resource = N'DBAPulse.RetentionCleanup', @LockMode = N'Exclusive', @LockOwner = N'Session', @LockTimeout = 0;
    IF @lockResult < 0 RETURN;

    BEGIN TRY
        SELECT @interval = CleanupIntervalHours, @last = LastCleanupAtUtc FROM dbo.RetentionSettings WHERE Id = 1;
        IF @interval IS NULL SET @interval = 24;
        IF @last IS NOT NULL AND @last > DATEADD(HOUR, -@interval, @now)
        BEGIN
            EXEC sp_releaseapplock @Resource = N'DBAPulse.RetentionCleanup', @LockOwner = N'Session';
            RETURN;
        END;

        SELECT @maxRetentionDays = ISNULL(MAX(RetentionDays), 30) FROM dbo.Servers;

        DECLARE @steps TABLE (Seq int NOT NULL PRIMARY KEY, Sql nvarchar(max) NOT NULL);
        INSERT @steps (Seq, Sql) VALUES
        (10, N'DELETE TOP (@batch) n FROM dbo.AlertNotificationDeliveries n JOIN dbo.OperationalEvents e ON e.Id=n.OperationalEventId JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        /* signals of an expiring group are removed too so the group delete cannot hit FK_ManagementRelatedSignals_Group */
        (20, N'DELETE TOP (@batch) rs FROM dbo.ManagementRelatedSignals rs JOIN dbo.Servers s ON s.Id=rs.ServerId WHERE rs.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now) OR EXISTS (SELECT 1 FROM dbo.ManagementCorrelationGroups g JOIN dbo.Servers gs ON gs.Id=g.ServerId WHERE g.Id=rs.CorrelationGroupId AND g.LastSeenAtUtc < DATEADD(DAY,-gs.RetentionDays,@now));'),
        (30, N'DELETE TOP (@batch) g FROM dbo.ManagementCorrelationGroups g JOIN dbo.Servers s ON s.Id=g.ServerId WHERE g.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (40, N'DELETE TOP (@batch) e FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (50, N'DELETE TOP (@batch) a FROM dbo.AnomalyFindings a JOIN dbo.Servers s ON s.Id=a.ServerId WHERE a.LastSeenAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (60, N'DELETE TOP (@batch) b FROM dbo.Baselines b JOIN dbo.Servers s ON s.Id=b.ServerId WHERE b.CalculatedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (70, N'DELETE TOP (@batch) x FROM dbo.BlockingEvents x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CapturedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (80, N'DELETE TOP (@batch) x FROM dbo.LongRunningRequestSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CapturedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (90, N'DELETE TOP (@batch) x FROM dbo.WaitStatsSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CapturedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (100, N'DELETE TOP (@batch) x FROM dbo.DeadlockEvents x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.OccurredAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (110, N'DELETE TOP (@batch) x FROM dbo.VolumeCapacitySnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (120, N'DELETE TOP (@batch) x FROM dbo.CapacitySnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (130, N'DELETE TOP (@batch) x FROM dbo.BackupSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (140, N'DELETE TOP (@batch) x FROM dbo.JobSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (150, N'DELETE TOP (@batch) x FROM dbo.AlwaysOnSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (160, N'DELETE TOP (@batch) x FROM dbo.ServerSnapshots x JOIN dbo.Servers s ON s.Id=x.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (170, N'DELETE TOP (@batch) x FROM dbo.DatabaseSnapshots x JOIN dbo.Databases d ON d.Id=x.DatabaseId JOIN dbo.Servers s ON s.Id=d.ServerId WHERE x.CollectedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        (180, N'DELETE TOP (@batch) e FROM dbo.CollectionErrors e JOIN dbo.Servers s ON s.ServerName=e.ServerName WHERE e.CreatedAtUtc < DATEADD(DAY,-s.RetentionDays,@now);'),
        /* errors whose ServerName matches no server (e.g. the source data source name) expire with the longest retention */
        (190, N'DELETE TOP (@batch) e FROM dbo.CollectionErrors e WHERE e.CreatedAtUtc < DATEADD(DAY,-@maxRetentionDays,@now);'),
        /* parents last: only runs older than the longest retention that no child row references any more */
        (200, N'DELETE TOP (@batch) r FROM dbo.CollectionRuns r WHERE r.StartedAtUtc < DATEADD(DAY,-@maxRetentionDays,@now)
            AND NOT EXISTS (SELECT 1 FROM dbo.CollectionErrors c WHERE c.CollectionRunId=r.Id)
            AND NOT EXISTS (SELECT 1 FROM dbo.ServerSnapshots c WHERE c.CollectionRunId=r.Id)
            AND NOT EXISTS (SELECT 1 FROM dbo.DatabaseSnapshots c WHERE c.CollectionRunId=r.Id)
            AND NOT EXISTS (SELECT 1 FROM dbo.BackupSnapshots c WHERE c.CollectionRunId=r.Id)
            AND NOT EXISTS (SELECT 1 FROM dbo.JobSnapshots c WHERE c.CollectionRunId=r.Id)
            AND NOT EXISTS (SELECT 1 FROM dbo.AlwaysOnSnapshots c WHERE c.CollectionRunId=r.Id)
            AND NOT EXISTS (SELECT 1 FROM dbo.CapacitySnapshots c WHERE c.CollectionRunId=r.Id);');

        SET @step = (SELECT MIN(Seq) FROM @steps);
        WHILE @step IS NOT NULL
        BEGIN
            SELECT @sql = Sql + N' SET @rows = @@ROWCOUNT;' FROM @steps WHERE Seq = @step;
            SET @rows = @batch;
            WHILE @rows >= @batch
            BEGIN
                EXEC sp_executesql @sql, N'@batch int, @now datetime2(3), @maxRetentionDays int, @rows int OUTPUT',
                     @batch = @batch, @now = @now, @maxRetentionDays = @maxRetentionDays, @rows = @rows OUTPUT;
            END;
            SET @step = (SELECT MIN(Seq) FROM @steps WHERE Seq > @step);
        END;

        UPDATE dbo.RetentionSettings SET LastCleanupAtUtc = @now WHERE Id = 1;
        EXEC sp_releaseapplock @Resource = N'DBAPulse.RetentionCleanup', @LockOwner = N'Session';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF APPLOCK_MODE(N'public', N'DBAPulse.RetentionCleanup', N'Session') <> N'NoLock'
            EXEC sp_releaseapplock @Resource = N'DBAPulse.RetentionCleanup', @LockOwner = N'Session';
        THROW;
    END CATCH;
END;
GO
