CREATE OR ALTER PROCEDURE dbo.usp_Servers_Sync
    @Rows dbo.ServerInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE s
       SET s.InstanceName = r.InstanceName,
           s.SqlVersion = r.SqlVersion,
           s.Edition = r.Edition,
           s.TimeZoneId = r.TimeZoneId,
           s.LastSeenAtUtc = r.LastSeenAtUtc,
           s.IsActive = r.IsActive
    FROM dbo.Servers AS s
    INNER JOIN @Rows AS r ON r.ServerName = s.ServerName;

    INSERT dbo.Servers (ServerName, InstanceName, SqlVersion, Edition, TimeZoneId, LastSeenAtUtc, IsActive)
    SELECT r.ServerName, r.InstanceName, r.SqlVersion, r.Edition, r.TimeZoneId, r.LastSeenAtUtc, r.IsActive
    FROM @Rows AS r
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Servers AS s WHERE s.ServerName = r.ServerName);

    SELECT s.Id, s.ServerName FROM dbo.Servers AS s INNER JOIN @Rows AS r ON r.ServerName = s.ServerName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Databases_Sync
    @Rows dbo.DatabaseInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE d
       SET d.RecoveryModel = r.RecoveryModel,
           d.DatabaseStatus = r.DatabaseStatus,
           d.LastSeenAtUtc = r.LastSeenAtUtc,
           d.IsActive = r.IsActive
    FROM dbo.Databases AS d
    INNER JOIN @Rows AS r ON r.ServerId = d.ServerId AND r.DatabaseName = d.DatabaseName;

    INSERT dbo.Databases (ServerId, DatabaseName, RecoveryModel, DatabaseStatus, LastSeenAtUtc, IsActive)
    SELECT r.ServerId, r.DatabaseName, r.RecoveryModel, r.DatabaseStatus, r.LastSeenAtUtc, r.IsActive
    FROM @Rows AS r
    WHERE NOT EXISTS
    (
        SELECT 1 FROM dbo.Databases AS d
        WHERE d.ServerId = r.ServerId AND d.DatabaseName = r.DatabaseName
    );

    SELECT d.Id, d.ServerId, d.DatabaseName
    FROM dbo.Databases AS d
    INNER JOIN @Rows AS r ON r.ServerId = d.ServerId AND r.DatabaseName = d.DatabaseName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServerSnapshots_Insert
    @Rows dbo.ServerSnapshotInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.ServerSnapshots (CollectionRunId, ServerId, CollectedAtUtc, UptimeSeconds)
    SELECT CollectionRunId, ServerId, CollectedAtUtc, UptimeSeconds FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DatabaseSnapshots_Insert
    @Rows dbo.DatabaseSnapshotInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.DatabaseSnapshots (CollectionRunId, DatabaseId, CollectedAtUtc, DatabaseStatus, UserAccess, CompatibilityLevel, IsReadOnly, IsEncrypted)
    SELECT CollectionRunId, DatabaseId, CollectedAtUtc, DatabaseStatus, UserAccess, CompatibilityLevel, IsReadOnly, IsEncrypted FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BackupSnapshots_Insert
    @Rows dbo.BackupSnapshotInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.BackupSnapshots (CollectionRunId, ServerId, DatabaseId, DatabaseName, CollectedAtUtc, BackupType, BackupStartAtSource, BackupFinishAtSource, BackupSizeMb, CompressedBackupSizeMb, IsCopyOnly)
    SELECT CollectionRunId, ServerId, DatabaseId, DatabaseName, CollectedAtUtc, BackupType, BackupStartAtSource, BackupFinishAtSource, BackupSizeMb, CompressedBackupSizeMb, IsCopyOnly FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_JobSnapshots_Insert
    @Rows dbo.JobSnapshotInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.JobSnapshots (CollectionRunId, ServerId, CollectedAtUtc, JobName, Enabled, LastRunStatus, LastRunAtSource, LastRunMessage)
    SELECT CollectionRunId, ServerId, CollectedAtUtc, JobName, Enabled, LastRunStatus, LastRunAtSource, LastRunMessage FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AlwaysOnSnapshots_Insert
    @Rows dbo.AlwaysOnSnapshotInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.AlwaysOnSnapshots (CollectionRunId, ServerId, CollectedAtUtc, AvailabilityGroupName, ReplicaServerName, RoleDescription, OperationalState, ConnectedState, SynchronizationHealth, DatabaseName, SynchronizationState, DatabaseState)
    SELECT CollectionRunId, ServerId, CollectedAtUtc, AvailabilityGroupName, ReplicaServerName, RoleDescription, OperationalState, ConnectedState, SynchronizationHealth, DatabaseName, SynchronizationState, DatabaseState FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CapacitySnapshots_Insert
    @Rows dbo.CapacitySnapshotInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.CapacitySnapshots (CollectionRunId, ServerId, DatabaseId, DatabaseName, CollectedAtUtc, FileType, AllocatedSizeMb, FileCount)
    SELECT CollectionRunId, ServerId, DatabaseId, DatabaseName, CollectedAtUtc, FileType, AllocatedSizeMb, FileCount FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CollectionRun_Start
    @StartedAtUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.CollectionRuns (StartedAtUtc, Status) VALUES (@StartedAtUtc, N'Running');
    SELECT CAST(SCOPE_IDENTITY() AS bigint) AS CollectionRunId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CollectionRun_Complete
    @CollectionRunId bigint,
    @Status nvarchar(30),
    @FinishedAtUtc datetime2(3),
    @DurationMs bigint
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.CollectionRuns
       SET Status = @Status, FinishedAtUtc = @FinishedAtUtc, DurationMs = @DurationMs
     WHERE Id = @CollectionRunId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CollectionError_Insert
    @CollectionRunId bigint,
    @QueryName nvarchar(256),
    @ErrorMessage nvarchar(4000),
    @ServerName nvarchar(256) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.CollectionErrors (CollectionRunId, QueryName, ServerName, ErrorMessage, CreatedAtUtc)
    VALUES (@CollectionRunId, @QueryName, @ServerName, @ErrorMessage, SYSUTCDATETIME());
END;
GO
