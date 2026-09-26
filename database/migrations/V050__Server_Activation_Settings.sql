CREATE OR ALTER PROCEDURE dbo.usp_Servers_Sync
    @Rows dbo.ServerInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE s
       SET s.InstanceName = r.InstanceName,
           s.SqlVersion = r.SqlVersion,
           s.Edition = r.Edition,
           s.TimeZoneId = r.TimeZoneId,
           s.LastSeenAtUtc = r.LastSeenAtUtc,
           s.IsActive = CASE WHEN s.IsActive = 0 THEN 0 ELSE r.IsActive END
    FROM dbo.Servers AS s
    INNER JOIN @Rows AS r ON r.ServerName = s.ServerName;

    INSERT dbo.Servers (ServerName, InstanceName, SqlVersion, Edition, TimeZoneId, LastSeenAtUtc, IsActive)
    SELECT r.ServerName, r.InstanceName, r.SqlVersion, r.Edition, r.TimeZoneId, r.LastSeenAtUtc, r.IsActive
    FROM @Rows AS r
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Servers AS s WHERE s.ServerName = r.ServerName);

    SELECT s.Id, s.ServerName FROM dbo.Servers AS s INNER JOIN @Rows AS r ON r.ServerName = s.ServerName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Server_Detail
    @ServerId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.Id AS ServerId, s.ServerName, s.InstanceName, s.SqlVersion, s.Edition, s.TimeZoneId, s.LastSeenAtUtc,
           COUNT(d.Id) AS DatabaseCount
    FROM dbo.Servers AS s
    LEFT JOIN dbo.Databases AS d ON d.ServerId = s.Id AND d.IsActive = 1
    WHERE s.Id = @ServerId AND s.IsActive = 1
    GROUP BY s.Id, s.ServerName, s.InstanceName, s.SqlVersion, s.Edition, s.TimeZoneId, s.LastSeenAtUtc;

    SELECT d.Id AS DatabaseId, d.DatabaseName, d.DatabaseStatus, d.RecoveryModel, d.LastSeenAtUtc
    FROM dbo.Databases AS d
    INNER JOIN dbo.Servers AS s ON s.Id = d.ServerId
    WHERE d.ServerId = @ServerId AND d.IsActive = 1 AND s.IsActive = 1
    ORDER BY d.DatabaseName;
END;
GO