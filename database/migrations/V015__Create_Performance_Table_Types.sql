CREATE TYPE dbo.BlockingEventInputType AS TABLE
(
    ServerId int NOT NULL, DatabaseId int NULL, CapturedAtUtc datetime2(3) NOT NULL,
    SessionId int NOT NULL, BlockingSessionId int NOT NULL, WaitType nvarchar(120) NULL,
    WaitDurationMs bigint NOT NULL, Command nvarchar(128) NULL, HostName nvarchar(256) NULL,
    ApplicationName nvarchar(256) NULL, LoginName nvarchar(256) NULL, SqlTextHash varchar(64) NULL,
    SqlTextPreview nvarchar(1500) NULL
);

CREATE TYPE dbo.LongRunningRequestInputType AS TABLE
(
    ServerId int NOT NULL, DatabaseId int NULL, CapturedAtUtc datetime2(3) NOT NULL,
    SessionId int NOT NULL, RequestStartTimeUtc datetime2(3) NULL, ElapsedMs bigint NOT NULL,
    Status nvarchar(60) NULL, Command nvarchar(128) NULL, WaitType nvarchar(120) NULL,
    WaitTimeMs bigint NULL, CpuTimeMs bigint NULL, LogicalReads bigint NULL, Reads bigint NULL,
    Writes bigint NULL, HostName nvarchar(256) NULL, ApplicationName nvarchar(256) NULL,
    LoginName nvarchar(256) NULL, SqlTextHash varchar(64) NULL, SqlTextPreview nvarchar(1500) NULL
);

CREATE TYPE dbo.WaitStatsSnapshotInputType AS TABLE
(
    ServerId int NOT NULL, CapturedAtUtc datetime2(3) NOT NULL, SqlServerStartTimeUtc datetime2(3) NOT NULL,
    WaitType nvarchar(120) NOT NULL, WaitTimeMs bigint NOT NULL, SignalWaitTimeMs bigint NOT NULL,
    WaitingTasksCount bigint NOT NULL
);

CREATE TYPE dbo.DeadlockEventInputType AS TABLE
(
    ServerId int NOT NULL, DatabaseId int NULL, OccurredAtUtc datetime2(3) NOT NULL,
    VictimProcessId nvarchar(256) NULL, VictimSessionId int NULL, ProcessCount int NOT NULL,
    DeadlockHash varchar(64) NOT NULL, DeadlockXml xml NOT NULL, CollectedAtUtc datetime2(3) NOT NULL
);
