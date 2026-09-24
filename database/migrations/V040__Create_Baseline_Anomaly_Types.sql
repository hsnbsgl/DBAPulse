CREATE TYPE dbo.BaselineInputType AS TABLE
(
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
    BaselineScope nvarchar(32) NOT NULL
);
GO
CREATE TYPE dbo.AnomalyFindingInputType AS TABLE
(
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
    SourceEntityId bigint NULL
);
