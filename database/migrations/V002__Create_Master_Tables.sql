CREATE TABLE dbo.Servers
(
    Id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Servers PRIMARY KEY,
    ServerName nvarchar(256) NOT NULL,
    InstanceName nvarchar(128) NOT NULL,
    SqlVersion nvarchar(128) NOT NULL,
    Edition nvarchar(256) NOT NULL,
    TimeZoneId nvarchar(128) NOT NULL CONSTRAINT DF_Servers_TimeZoneId DEFAULT N'Europe/Istanbul',
    LastSeenAtUtc datetime2(3) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Servers_IsActive DEFAULT (1)
);

CREATE TABLE dbo.Databases
(
    Id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Databases PRIMARY KEY,
    ServerId int NOT NULL,
    DatabaseName nvarchar(256) NOT NULL,
    RecoveryModel nvarchar(60) NOT NULL,
    DatabaseStatus nvarchar(60) NOT NULL,
    LastSeenAtUtc datetime2(3) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Databases_IsActive DEFAULT (1),
    CONSTRAINT UQ_Databases_Server_Database UNIQUE (ServerId, DatabaseName),
    CONSTRAINT FK_Databases_Servers FOREIGN KEY (ServerId) REFERENCES dbo.Servers(Id)
);
GO
