IF DB_ID(N'DBA_PULSE') IS NULL
BEGIN
    CREATE DATABASE [DBA_PULSE];
END;
GO
USE [DBA_PULSE];
GO
IF OBJECT_ID(N'dbo.SchemaVersions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SchemaVersions
    (
        Version nvarchar(20) NOT NULL CONSTRAINT PK_SchemaVersions PRIMARY KEY,
        Name nvarchar(200) NOT NULL,
        AppliedAtUtc datetime2(3) NOT NULL CONSTRAINT DF_SchemaVersions_AppliedAtUtc DEFAULT SYSUTCDATETIME()
    );
END;
GO
