CREATE OR ALTER PROCEDURE dbo.usp_OperationalEvents_Overview
    @Hours int = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET @Hours = CASE WHEN @Hours IN (1, 6, 12, 24, 48, 168) THEN @Hours ELSE 24 END;
    DECLARE @Since datetime2(3) = DATEADD(HOUR, -@Hours, SYSUTCDATETIME());
    SELECT
      COALESCE(SUM(CASE WHEN Status = N'Active' THEN 1 ELSE 0 END),0) AS ActiveEventCount,
      COALESCE(SUM(CASE WHEN Status = N'Active' AND Severity = N'Critical' THEN 1 ELSE 0 END),0) AS ActiveCriticalCount,
      COALESCE(SUM(CASE WHEN Status = N'Active' AND Severity = N'Warning' THEN 1 ELSE 0 END),0) AS ActiveWarningCount,
      COALESCE(SUM(CASE WHEN Status = N'Resolved' AND EndedAtUtc >= @Since THEN 1 ELSE 0 END),0) AS ResolvedEventCount,
      COALESCE(SUM(CASE WHEN EventType = N'Blocking' AND StartedAtUtc >= @Since THEN 1 ELSE 0 END),0) AS BlockingEventCount,
      COALESCE(SUM(CASE WHEN EventType = N'LongRunning' AND StartedAtUtc >= @Since THEN 1 ELSE 0 END),0) AS LongRunningEventCount,
      COALESCE(SUM(CASE WHEN EventType = N'Deadlock' AND StartedAtUtc >= @Since THEN 1 ELSE 0 END),0) AS DeadlockEventCount
    FROM dbo.OperationalEvents;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_OperationalEvents_List
    @FromUtc datetime2(3) = NULL, @ToUtc datetime2(3) = NULL, @Status nvarchar(20) = NULL,
    @Severity nvarchar(20) = NULL, @EventType nvarchar(40) = NULL, @ServerId int = NULL, @DatabaseId int = NULL,
    @Page int = 1, @PageSize int = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET @Page = CASE WHEN @Page < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN @PageSize < 1 THEN 50 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SELECT e.Id, e.EventType, s.ServerName, d.DatabaseName, e.Fingerprint, e.StartedAtUtc, e.LastSeenAtUtc, e.EndedAtUtc,
           e.DurationMs, e.Status, e.Severity, e.ObservationCount, e.AffectedSessionCount, e.Title, e.Summary
    FROM dbo.OperationalEvents AS e INNER JOIN dbo.Servers AS s ON s.Id = e.ServerId LEFT JOIN dbo.Databases AS d ON d.Id = e.DatabaseId
    WHERE (@FromUtc IS NULL OR e.StartedAtUtc >= @FromUtc) AND (@ToUtc IS NULL OR e.StartedAtUtc <= @ToUtc)
      AND (@Status IS NULL OR e.Status = @Status) AND (@Severity IS NULL OR e.Severity = @Severity)
      AND (@EventType IS NULL OR e.EventType = @EventType) AND (@ServerId IS NULL OR e.ServerId = @ServerId) AND (@DatabaseId IS NULL OR e.DatabaseId = @DatabaseId)
    ORDER BY CASE WHEN e.Status = N'Active' THEN 0 ELSE 1 END, e.LastSeenAtUtc DESC, e.Id DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    SELECT COUNT(*) AS TotalCount FROM dbo.OperationalEvents AS e
    WHERE (@FromUtc IS NULL OR e.StartedAtUtc >= @FromUtc) AND (@ToUtc IS NULL OR e.StartedAtUtc <= @ToUtc)
      AND (@Status IS NULL OR e.Status = @Status) AND (@Severity IS NULL OR e.Severity = @Severity)
      AND (@EventType IS NULL OR e.EventType = @EventType) AND (@ServerId IS NULL OR e.ServerId = @ServerId) AND (@DatabaseId IS NULL OR e.DatabaseId = @DatabaseId);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_OperationalEvent_Detail @Id bigint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.Id, e.EventType, s.ServerName, d.DatabaseName, e.Fingerprint, e.StartedAtUtc, e.LastSeenAtUtc, e.EndedAtUtc,
           e.DurationMs, e.Status, e.Severity, e.ObservationCount, e.AffectedSessionCount, e.Title, e.Summary,
           e.SourceEntityId, e.CreatedAtUtc, e.UpdatedAtUtc, e.AdditionalData
    FROM dbo.OperationalEvents AS e INNER JOIN dbo.Servers AS s ON s.Id = e.ServerId LEFT JOIN dbo.Databases AS d ON d.Id = e.DatabaseId
    WHERE e.Id = @Id;
END;
