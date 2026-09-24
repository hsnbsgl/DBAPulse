DROP PROCEDURE IF EXISTS dbo.usp_LongRunningRequests_Insert;
DROP TYPE IF EXISTS dbo.LongRunningRequestInputType;
IF COL_LENGTH(N'dbo.LongRunningRequestSnapshots', N'RequestStartTimeSource') IS NULL
    ALTER TABLE dbo.LongRunningRequestSnapshots ADD RequestStartTimeSource datetime2(3) NULL;
GO

IF COL_LENGTH(N'dbo.LongRunningRequestSnapshots', N'RequestStartTimeUtc') IS NOT NULL
    UPDATE dbo.LongRunningRequestSnapshots SET RequestStartTimeSource = RequestStartTimeUtc;
GO

IF COL_LENGTH(N'dbo.LongRunningRequestSnapshots', N'RequestStartTimeUtc') IS NOT NULL
    ALTER TABLE dbo.LongRunningRequestSnapshots DROP COLUMN RequestStartTimeUtc;
GO

CREATE TYPE dbo.LongRunningRequestInputType AS TABLE
(
    ServerId int NOT NULL, DatabaseId int NULL, CapturedAtUtc datetime2(3) NOT NULL,
    SessionId int NOT NULL, RequestStartTimeSource datetime2(3) NULL, ElapsedMs bigint NOT NULL,
    Status nvarchar(60) NULL, Command nvarchar(128) NULL, WaitType nvarchar(120) NULL,
    WaitTimeMs bigint NULL, CpuTimeMs bigint NULL, LogicalReads bigint NULL, Reads bigint NULL,
    Writes bigint NULL, HostName nvarchar(256) NULL, ApplicationName nvarchar(256) NULL,
    LoginName nvarchar(256) NULL, SqlTextHash varchar(64) NULL, SqlTextPreview nvarchar(1500) NULL
);
GO

CREATE OR ALTER PROCEDURE dbo.usp_LongRunningRequests_Insert
    @Rows dbo.LongRunningRequestInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.LongRunningRequestSnapshots (ServerId, DatabaseId, CapturedAtUtc, SessionId, RequestStartTimeSource, ElapsedMs, Status, Command, WaitType, WaitTimeMs, CpuTimeMs, LogicalReads, Reads, Writes, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview)
    SELECT ServerId, DatabaseId, CapturedAtUtc, SessionId, RequestStartTimeSource, ElapsedMs, Status, Command, WaitType, WaitTimeMs, CpuTimeMs, LogicalReads, Reads, Writes, HostName, ApplicationName, LoginName, SqlTextHash, SqlTextPreview FROM @Rows;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
