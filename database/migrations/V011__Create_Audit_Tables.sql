CREATE TABLE dbo.AuditLogs
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLogs PRIMARY KEY,
    OccurredAtUtc datetime2(3) NOT NULL,
    UserName nvarchar(256) NOT NULL,
    UserRole nvarchar(128) NULL,
    Action nvarchar(128) NOT NULL,
    ResourceType nvarchar(64) NOT NULL,
    ResourceId nvarchar(128) NULL,
    HttpMethod nvarchar(16) NOT NULL,
    RequestPath nvarchar(512) NOT NULL,
    Result nvarchar(16) NOT NULL,
    StatusCode int NOT NULL,
    DurationMs bigint NOT NULL,
    CorrelationId nvarchar(64) NOT NULL,
    ClientIp nvarchar(128) NULL,
    UserAgent nvarchar(512) NULL,
    AdditionalData nvarchar(2000) NULL,
    CONSTRAINT CK_AuditLogs_Result CHECK (Result IN (N'Success', N'Failed', N'Denied'))
);
GO
