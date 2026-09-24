CREATE TYPE dbo.ServerInputType AS TABLE
(
    ServerName nvarchar(256) NOT NULL PRIMARY KEY,
    InstanceName nvarchar(128) NOT NULL,
    SqlVersion nvarchar(128) NOT NULL,
    Edition nvarchar(256) NOT NULL,
    TimeZoneId nvarchar(128) NOT NULL,
    LastSeenAtUtc datetime2(3) NOT NULL,
    IsActive bit NOT NULL
);

CREATE TYPE dbo.DatabaseInputType AS TABLE
(
    ServerId int NOT NULL,
    DatabaseName nvarchar(256) NOT NULL,
    RecoveryModel nvarchar(60) NOT NULL,
    DatabaseStatus nvarchar(60) NOT NULL,
    LastSeenAtUtc datetime2(3) NOT NULL,
    IsActive bit NOT NULL,
    PRIMARY KEY (ServerId, DatabaseName)
);

CREATE TYPE dbo.ServerSnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL,
    ServerId int NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    UptimeSeconds bigint NULL
);

CREATE TYPE dbo.DatabaseSnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL,
    DatabaseId int NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    DatabaseStatus nvarchar(60) NOT NULL,
    UserAccess nvarchar(60) NULL,
    CompatibilityLevel int NULL,
    IsReadOnly bit NULL,
    IsEncrypted bit NULL
);

CREATE TYPE dbo.BackupSnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL,
    ServerId int NOT NULL,
    DatabaseId int NULL,
    DatabaseName nvarchar(256) NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    BackupType nvarchar(30) NOT NULL,
    BackupStartAtSource datetime2(3) NULL,
    BackupFinishAtSource datetime2(3) NULL,
    BackupSizeMb decimal(19,2) NULL,
    CompressedBackupSizeMb decimal(19,2) NULL,
    IsCopyOnly bit NOT NULL
);

CREATE TYPE dbo.JobSnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL,
    ServerId int NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    JobName nvarchar(256) NOT NULL,
    Enabled bit NOT NULL,
    LastRunStatus nvarchar(30) NOT NULL,
    LastRunAtSource datetime2(3) NULL,
    LastRunMessage nvarchar(4000) NULL
);

CREATE TYPE dbo.AlwaysOnSnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL,
    ServerId int NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    AvailabilityGroupName nvarchar(256) NULL,
    ReplicaServerName nvarchar(256) NULL,
    RoleDescription nvarchar(60) NULL,
    OperationalState nvarchar(60) NULL,
    ConnectedState nvarchar(60) NULL,
    SynchronizationHealth nvarchar(60) NULL,
    DatabaseName nvarchar(256) NULL,
    SynchronizationState nvarchar(60) NULL,
    DatabaseState nvarchar(60) NULL
);

CREATE TYPE dbo.CapacitySnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL,
    ServerId int NOT NULL,
    DatabaseId int NULL,
    DatabaseName nvarchar(256) NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    FileType nvarchar(60) NOT NULL,
    AllocatedSizeMb decimal(19,2) NOT NULL,
    FileCount int NOT NULL
);
GO
