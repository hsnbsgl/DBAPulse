CREATE TYPE dbo.BackupProtectionSnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL, ServerId int NOT NULL, DatabaseId int NULL, DatabaseName nvarchar(256) NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL, BackupType nvarchar(30) NOT NULL, BackupStartAtSource datetime2(3) NULL,
    BackupFinishAtSource datetime2(3) NULL, BackupSizeMb decimal(19,2) NULL, CompressedBackupSizeMb decimal(19,2) NULL,
    IsCopyOnly bit NOT NULL, BackupDurationSeconds int NULL
);
CREATE TYPE dbo.JobHealthSnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL, ServerId int NOT NULL, CollectedAtUtc datetime2(3) NOT NULL, JobId nvarchar(36) NOT NULL,
    JobName nvarchar(256) NOT NULL, Enabled bit NOT NULL, LastRunStatus nvarchar(30) NOT NULL, LastRunAtSource datetime2(3) NULL,
    LastRunDurationSeconds int NULL, LastRunMessage nvarchar(4000) NULL, IsRunning bit NOT NULL, CurrentStartAtSource datetime2(3) NULL,
    CurrentDurationSeconds int NULL, NextRunAtSource datetime2(3) NULL, FailureCount24Hours int NOT NULL, FailureCount7Days int NOT NULL,
    RepeatedFailure bit NOT NULL, AverageDurationSeconds int NULL, MaxDurationSeconds int NULL
);
CREATE TYPE dbo.AlwaysOnTelemetryInputType AS TABLE
(
    CollectionRunId bigint NOT NULL, ServerId int NOT NULL, CollectedAtUtc datetime2(3) NOT NULL, AvailabilityGroupName nvarchar(256) NULL,
    ReplicaServerName nvarchar(256) NULL, RoleDescription nvarchar(60) NULL, OperationalState nvarchar(60) NULL, ConnectedState nvarchar(60) NULL,
    SynchronizationHealth nvarchar(60) NULL, DatabaseName nvarchar(256) NULL, SynchronizationState nvarchar(60) NULL, DatabaseState nvarchar(60) NULL,
    IsSuspended bit NOT NULL, SuspendReason nvarchar(256) NULL, LogSendQueueMb decimal(19,2) NULL, RedoQueueMb decimal(19,2) NULL,
    LogSendRateMb decimal(19,2) NULL, RedoRateMb decimal(19,2) NULL, LastCommitTimeSource datetime2(3) NULL
);
