CREATE OR ALTER PROCEDURE dbo.usp_BackupProtectionSnapshots_Insert @Rows dbo.BackupProtectionSnapshotInputType READONLY AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.BackupSnapshots (CollectionRunId,ServerId,DatabaseId,DatabaseName,CollectedAtUtc,BackupType,BackupStartAtSource,BackupFinishAtSource,BackupSizeMb,CompressedBackupSizeMb,IsCopyOnly,BackupDurationSeconds)
 SELECT CollectionRunId,ServerId,DatabaseId,DatabaseName,CollectedAtUtc,BackupType,BackupStartAtSource,BackupFinishAtSource,BackupSizeMb,CompressedBackupSizeMb,IsCopyOnly,BackupDurationSeconds FROM @Rows;
 SELECT CAST(@@ROWCOUNT AS int);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_JobHealthSnapshots_Insert @Rows dbo.JobHealthSnapshotInputType READONLY AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.JobSnapshots (CollectionRunId,ServerId,CollectedAtUtc,JobId,JobName,Enabled,LastRunStatus,LastRunAtSource,LastRunDurationSeconds,LastRunMessage,IsRunning,CurrentStartAtSource,CurrentDurationSeconds,NextRunAtSource,FailureCount24Hours,FailureCount7Days,RepeatedFailure,AverageDurationSeconds,MaxDurationSeconds)
 SELECT CollectionRunId,ServerId,CollectedAtUtc,JobId,JobName,Enabled,LastRunStatus,LastRunAtSource,LastRunDurationSeconds,LastRunMessage,IsRunning,CurrentStartAtSource,CurrentDurationSeconds,NextRunAtSource,FailureCount24Hours,FailureCount7Days,RepeatedFailure,AverageDurationSeconds,MaxDurationSeconds FROM @Rows;
 SELECT CAST(@@ROWCOUNT AS int);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_AlwaysOnTelemetry_Insert @Rows dbo.AlwaysOnTelemetryInputType READONLY AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AlwaysOnSnapshots (CollectionRunId,ServerId,CollectedAtUtc,AvailabilityGroupName,ReplicaServerName,RoleDescription,OperationalState,ConnectedState,SynchronizationHealth,DatabaseName,SynchronizationState,DatabaseState,IsSuspended,SuspendReason,LogSendQueueMb,RedoQueueMb,LogSendRateMb,RedoRateMb,LastCommitTimeSource)
 SELECT CollectionRunId,ServerId,CollectedAtUtc,AvailabilityGroupName,ReplicaServerName,RoleDescription,OperationalState,ConnectedState,SynchronizationHealth,DatabaseName,SynchronizationState,DatabaseState,IsSuspended,SuspendReason,LogSendQueueMb,RedoQueueMb,LogSendRateMb,RedoRateMb,LastCommitTimeSource FROM @Rows;
 SELECT CAST(@@ROWCOUNT AS int);
END;
