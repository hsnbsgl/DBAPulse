IF COL_LENGTH('dbo.BackupSnapshots', 'BackupDurationSeconds') IS NULL
    ALTER TABLE dbo.BackupSnapshots ADD BackupDurationSeconds int NULL;
IF COL_LENGTH('dbo.JobSnapshots', 'JobId') IS NULL
    ALTER TABLE dbo.JobSnapshots ADD JobId nvarchar(36) NULL, LastRunDurationSeconds int NULL, IsRunning bit NOT NULL CONSTRAINT DF_JobSnapshots_IsRunning DEFAULT(0), CurrentStartAtSource datetime2(3) NULL, CurrentDurationSeconds int NULL, NextRunAtSource datetime2(3) NULL, FailureCount24Hours int NOT NULL CONSTRAINT DF_JobSnapshots_FailureCount24Hours DEFAULT(0), FailureCount7Days int NOT NULL CONSTRAINT DF_JobSnapshots_FailureCount7Days DEFAULT(0), RepeatedFailure bit NOT NULL CONSTRAINT DF_JobSnapshots_RepeatedFailure DEFAULT(0), AverageDurationSeconds int NULL, MaxDurationSeconds int NULL;
IF COL_LENGTH('dbo.AlwaysOnSnapshots', 'IsSuspended') IS NULL
    ALTER TABLE dbo.AlwaysOnSnapshots ADD IsSuspended bit NOT NULL CONSTRAINT DF_AlwaysOnSnapshots_IsSuspended DEFAULT(0), SuspendReason nvarchar(256) NULL, LogSendQueueMb decimal(19,2) NULL, RedoQueueMb decimal(19,2) NULL, LogSendRateMb decimal(19,2) NULL, RedoRateMb decimal(19,2) NULL, LastCommitTimeSource datetime2(3) NULL;

IF OBJECT_ID('dbo.BackupPolicies', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupPolicies
    (
        Id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_BackupPolicies PRIMARY KEY,
        PolicyName nvarchar(128) NOT NULL CONSTRAINT UQ_BackupPolicies_PolicyName UNIQUE,
        FullBackupMaxAgeHours int NULL,
        DifferentialBackupMaxAgeHours int NULL,
        LogBackupMaxAgeMinutes int NULL,
        WarningPercentage int NOT NULL CONSTRAINT DF_BackupPolicies_WarningPercentage DEFAULT(80),
        IsEnabled bit NOT NULL CONSTRAINT DF_BackupPolicies_IsEnabled DEFAULT(1),
        CreatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_BackupPolicies_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
        UpdatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_BackupPolicies_UpdatedAtUtc DEFAULT SYSUTCDATETIME()
    );
    INSERT dbo.BackupPolicies (PolicyName, FullBackupMaxAgeHours, DifferentialBackupMaxAgeHours, LogBackupMaxAgeMinutes)
    VALUES (N'Default', 24, NULL, 60);
END;
