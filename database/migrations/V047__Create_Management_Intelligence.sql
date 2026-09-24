CREATE TABLE dbo.ManagementCorrelationGroups
(
 Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ManagementCorrelationGroups PRIMARY KEY,
 GroupFingerprint varchar(64) NOT NULL CONSTRAINT UQ_ManagementCorrelationGroups_Fingerprint UNIQUE,
 ServerId int NOT NULL, DatabaseId int NULL, WindowStartUtc datetime2(3) NOT NULL, WindowEndUtc datetime2(3) NOT NULL, LastSeenAtUtc datetime2(3) NOT NULL,
 SignalCount int NOT NULL CONSTRAINT DF_ManagementCorrelationGroups_SignalCount DEFAULT(0),
 Status nvarchar(20) NOT NULL CONSTRAINT DF_ManagementCorrelationGroups_Status DEFAULT(N'Active'),
 CreatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_ManagementCorrelationGroups_CreatedAtUtc DEFAULT(SYSUTCDATETIME()),
 UpdatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_ManagementCorrelationGroups_UpdatedAtUtc DEFAULT(SYSUTCDATETIME()),
 CONSTRAINT CK_ManagementCorrelationGroups_Status CHECK (Status IN (N'Active',N'Resolved')),
 CONSTRAINT FK_ManagementCorrelationGroups_Server FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id),
 CONSTRAINT FK_ManagementCorrelationGroups_Database FOREIGN KEY (DatabaseId) REFERENCES dbo.Databases(Id)
);
CREATE TABLE dbo.ManagementRelatedSignals
(
 Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ManagementRelatedSignals PRIMARY KEY,
 CorrelationGroupId bigint NOT NULL, SignalType nvarchar(64) NOT NULL, Domain nvarchar(32) NOT NULL, SignalId bigint NOT NULL,
 ServerId int NOT NULL, DatabaseId int NULL, Severity nvarchar(20) NOT NULL, Status nvarchar(20) NOT NULL,
 StartedAtUtc datetime2(3) NOT NULL, LastSeenAtUtc datetime2(3) NOT NULL, Title nvarchar(256) NOT NULL, SourceType nvarchar(64) NOT NULL,
 CorrelationStrength nvarchar(20) NOT NULL, TimeDifferenceSeconds int NOT NULL,
 CreatedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_ManagementRelatedSignals_CreatedAtUtc DEFAULT(SYSUTCDATETIME()),
 CONSTRAINT UQ_ManagementRelatedSignals_GroupSignal UNIQUE(CorrelationGroupId,SourceType,SignalId),
 CONSTRAINT FK_ManagementRelatedSignals_Group FOREIGN KEY (CorrelationGroupId) REFERENCES dbo.ManagementCorrelationGroups(Id)
);