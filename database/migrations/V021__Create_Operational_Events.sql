CREATE TABLE dbo.OperationalEvents
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_OperationalEvents PRIMARY KEY,
    EventType nvarchar(40) NOT NULL,
    ServerId int NOT NULL,
    DatabaseId int NULL,
    Fingerprint varchar(64) NOT NULL,
    StartedAtUtc datetime2(3) NOT NULL,
    LastSeenAtUtc datetime2(3) NOT NULL,
    EndedAtUtc datetime2(3) NULL,
    DurationMs bigint NOT NULL,
    Status nvarchar(20) NOT NULL,
    Severity nvarchar(20) NOT NULL,
    ObservationCount int NOT NULL,
    AffectedSessionCount int NULL,
    Title nvarchar(256) NOT NULL,
    Summary nvarchar(1000) NOT NULL,
    SourceEntityId bigint NULL,
    CreatedAtUtc datetime2(3) NOT NULL,
    UpdatedAtUtc datetime2(3) NOT NULL,
    AdditionalData nvarchar(2000) NULL,
    CONSTRAINT FK_OperationalEvents_Server FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id),
    CONSTRAINT FK_OperationalEvents_Database FOREIGN KEY (DatabaseId) REFERENCES dbo.Databases(Id),
    CONSTRAINT CK_OperationalEvents_Status CHECK (Status IN (N'Active', N'Resolved')),
    CONSTRAINT CK_OperationalEvents_Severity CHECK (Severity IN (N'Info', N'Warning', N'Critical'))
);

CREATE TABLE dbo.WaitTypeExclusions
(
    WaitType nvarchar(120) NOT NULL CONSTRAINT PK_WaitTypeExclusions PRIMARY KEY,
    Reason nvarchar(500) NOT NULL,
    IsEnabled bit NOT NULL CONSTRAINT DF_WaitTypeExclusions_IsEnabled DEFAULT (1),
    CreatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_WaitTypeExclusions_CreatedAtUtc DEFAULT (SYSUTCDATETIME())
);
