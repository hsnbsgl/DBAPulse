CREATE TABLE dbo.AnomalyPolicies
(
    MetricType nvarchar(64) NOT NULL CONSTRAINT PK_AnomalyPolicies PRIMARY KEY,
    WarningPercentile decimal(5,4) NOT NULL,
    CriticalPercentile decimal(5,4) NOT NULL,
    WarningModifiedZ decimal(12,4) NOT NULL,
    CriticalModifiedZ decimal(12,4) NOT NULL,
    MinObservedValue decimal(28,6) NOT NULL CONSTRAINT DF_AnomalyPolicies_MinObservedValue DEFAULT(0),
    IsEnabled bit NOT NULL CONSTRAINT DF_AnomalyPolicies_IsEnabled DEFAULT(1),
    UpdatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_AnomalyPolicies_UpdatedAtUtc DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.Baselines
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_Baselines PRIMARY KEY,
    MetricType nvarchar(64) NOT NULL,
    ServerId int NOT NULL,
    DatabaseId int NULL,
    EntityKey nvarchar(256) NULL,
    DayOfWeek tinyint NULL,
    HourOfDay tinyint NULL,
    WindowDays int NOT NULL,
    SampleCount int NOT NULL,
    MedianValue decimal(28,6) NOT NULL,
    P75Value decimal(28,6) NOT NULL,
    P90Value decimal(28,6) NOT NULL,
    P95Value decimal(28,6) NOT NULL,
    P99Value decimal(28,6) NOT NULL,
    MeanValue decimal(28,6) NOT NULL,
    StdDevValue decimal(28,6) NOT NULL,
    MadValue decimal(28,6) NOT NULL,
    MinValue decimal(28,6) NOT NULL,
    MaxValue decimal(28,6) NOT NULL,
    CalculatedAtUtc datetime2(3) NOT NULL,
    ValidFromUtc datetime2(3) NOT NULL,
    Status nvarchar(24) NOT NULL,
    BaselineScope nvarchar(32) NOT NULL,
    CONSTRAINT FK_Baselines_Server FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id),
    CONSTRAINT FK_Baselines_Database FOREIGN KEY (DatabaseId) REFERENCES dbo.Databases(Id),
    CONSTRAINT CK_Baselines_Status CHECK (Status IN (N'Usable', N'InsufficientData', N'Stale')),
    CONSTRAINT CK_Baselines_Scope CHECK (BaselineScope IN (N'Global', N'Seasonal'))
);

CREATE TABLE dbo.AnomalyFindings
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_AnomalyFindings PRIMARY KEY,
    MetricType nvarchar(64) NOT NULL,
    ServerId int NOT NULL,
    DatabaseId int NULL,
    EntityKey nvarchar(256) NULL,
    ObservedAtUtc datetime2(3) NOT NULL,
    ObservedValue decimal(28,6) NOT NULL,
    BaselineMedian decimal(28,6) NOT NULL,
    BaselineP95 decimal(28,6) NOT NULL,
    BaselineP99 decimal(28,6) NOT NULL,
    BaselineMad decimal(28,6) NOT NULL,
    DeviationRatio decimal(28,6) NULL,
    ModifiedZScore decimal(28,6) NULL,
    BaselineScope nvarchar(32) NOT NULL,
    SampleCount int NOT NULL,
    Severity nvarchar(20) NOT NULL,
    Status nvarchar(20) NOT NULL,
    ExplanationCode nvarchar(64) NOT NULL,
    Fingerprint varchar(64) NOT NULL,
    StartedAtUtc datetime2(3) NOT NULL,
    LastSeenAtUtc datetime2(3) NOT NULL,
    EndedAtUtc datetime2(3) NULL,
    ObservationCount int NOT NULL CONSTRAINT DF_AnomalyFindings_ObservationCount DEFAULT(1),
    NormalSampleCount int NOT NULL CONSTRAINT DF_AnomalyFindings_NormalSampleCount DEFAULT(0),
    SourceEntityId bigint NULL,
    CreatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_AnomalyFindings_CreatedAtUtc DEFAULT SYSUTCDATETIME(),
    UpdatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_AnomalyFindings_UpdatedAtUtc DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_AnomalyFindings_Server FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id),
    CONSTRAINT FK_AnomalyFindings_Database FOREIGN KEY (DatabaseId) REFERENCES dbo.Databases(Id),
    CONSTRAINT CK_AnomalyFindings_Status CHECK (Status IN (N'Active', N'Resolved')),
    CONSTRAINT CK_AnomalyFindings_Severity CHECK (Severity IN (N'Info', N'Warning', N'Critical'))
);

INSERT dbo.AnomalyPolicies (MetricType, WarningPercentile, CriticalPercentile, WarningModifiedZ, CriticalModifiedZ, MinObservedValue)
VALUES
(N'BlockingDuration', .95, .99, 3, 6, 1000),
(N'BlockingFrequency', .95, .99, 3, 6, 1),
(N'LongRunningDuration', .95, .99, 3, 6, 1000),
(N'WaitDelta', .95, .99, 3, 6, 1),
(N'JobDuration', .95, .99, 3, 6, 1),
(N'BackupDuration', .95, .99, 3, 6, 1),
(N'DatabaseGrowth', .95, .99, 3, 6, 1);
