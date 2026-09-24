CREATE TYPE dbo.OperationalEventInputType AS TABLE
(
    EventType nvarchar(40) NOT NULL,
    ServerId int NOT NULL,
    DatabaseId int NULL,
    Fingerprint varchar(64) NOT NULL,
    StartedAtUtc datetime2(3) NOT NULL,
    LastSeenAtUtc datetime2(3) NOT NULL,
    DurationMs bigint NOT NULL,
    Status nvarchar(20) NOT NULL,
    Severity nvarchar(20) NOT NULL,
    ObservationIncrement int NOT NULL,
    AffectedSessionCount int NULL,
    Title nvarchar(256) NOT NULL,
    Summary nvarchar(1000) NOT NULL,
    SourceEntityId bigint NULL,
    AdditionalData nvarchar(2000) NULL
);
