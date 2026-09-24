CREATE TABLE dbo.ServerSnapshots
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ServerSnapshots PRIMARY KEY,
    CollectionRunId bigint NULL,
    ServerId int NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    UptimeSeconds bigint NULL
);

CREATE TABLE dbo.DatabaseSnapshots
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_DatabaseSnapshots PRIMARY KEY,
    CollectionRunId bigint NULL,
    DatabaseId int NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    DatabaseStatus nvarchar(60) NOT NULL,
    UserAccess nvarchar(60) NULL,
    CompatibilityLevel int NULL,
    IsReadOnly bit NULL,
    IsEncrypted bit NULL
);

CREATE TABLE dbo.BackupSnapshots
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_BackupSnapshots PRIMARY KEY,
    CollectionRunId bigint NULL,
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

CREATE TABLE dbo.JobSnapshots
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_JobSnapshots PRIMARY KEY,
    CollectionRunId bigint NULL,
    ServerId int NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    JobName nvarchar(256) NOT NULL,
    Enabled bit NOT NULL,
    LastRunStatus nvarchar(30) NOT NULL,
    LastRunAtSource datetime2(3) NULL,
    LastRunMessage nvarchar(4000) NULL
);

CREATE TABLE dbo.AlwaysOnSnapshots
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_AlwaysOnSnapshots PRIMARY KEY,
    CollectionRunId bigint NULL,
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

CREATE TABLE dbo.CapacitySnapshots
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_CapacitySnapshots PRIMARY KEY,
    CollectionRunId bigint NULL,
    ServerId int NOT NULL,
    DatabaseId int NULL,
    DatabaseName nvarchar(256) NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    FileType nvarchar(60) NOT NULL,
    AllocatedSizeMb decimal(19,2) NOT NULL,
    FileCount int NOT NULL
);
GO
