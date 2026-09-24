CREATE OR ALTER PROCEDURE dbo.usp_OperationalEvents_Upsert
    @Rows dbo.OperationalEventInputType READONLY,
    @AsOfUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    UPDATE e
       SET e.LastSeenAtUtc = CASE WHEN r.LastSeenAtUtc > e.LastSeenAtUtc THEN r.LastSeenAtUtc ELSE e.LastSeenAtUtc END,
           e.DurationMs = DATEDIFF_BIG(MILLISECOND, e.StartedAtUtc, CASE WHEN r.LastSeenAtUtc > e.LastSeenAtUtc THEN r.LastSeenAtUtc ELSE e.LastSeenAtUtc END),
           e.ObservationCount = e.ObservationCount + r.ObservationIncrement,
           e.AffectedSessionCount = COALESCE(r.AffectedSessionCount, e.AffectedSessionCount),
           e.Severity = r.Severity,
           e.Status = N'Active',
           e.EndedAtUtc = NULL,
           e.UpdatedAtUtc = @AsOfUtc
    FROM dbo.OperationalEvents AS e WITH (UPDLOCK)
    INNER JOIN @Rows AS r ON r.Fingerprint = e.Fingerprint AND r.EventType = e.EventType
    WHERE e.Status = N'Active' AND r.Status = N'Active';

    INSERT dbo.OperationalEvents (EventType, ServerId, DatabaseId, Fingerprint, StartedAtUtc, LastSeenAtUtc, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary, SourceEntityId, CreatedAtUtc, UpdatedAtUtc, AdditionalData)
    SELECT r.EventType, r.ServerId, r.DatabaseId, r.Fingerprint, r.StartedAtUtc, r.LastSeenAtUtc, r.DurationMs, r.Status, r.Severity, r.ObservationIncrement, r.AffectedSessionCount, r.Title, r.Summary, r.SourceEntityId, @AsOfUtc, @AsOfUtc, r.AdditionalData
    FROM @Rows AS r
    WHERE NOT EXISTS (SELECT 1 FROM dbo.OperationalEvents AS e WHERE e.EventType = r.EventType AND e.Fingerprint = r.Fingerprint AND (e.Status = N'Active' OR r.EventType = N'Deadlock'));
    COMMIT TRANSACTION;
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_OperationalEvents_ResolveStale
    @EventType nvarchar(40),
    @AfterSeconds int,
    @AsOfUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET @AfterSeconds = CASE WHEN @AfterSeconds < 1 THEN 1 ELSE @AfterSeconds END;
    UPDATE dbo.OperationalEvents
       SET Status = N'Resolved', EndedAtUtc = LastSeenAtUtc,
           DurationMs = DATEDIFF_BIG(MILLISECOND, StartedAtUtc, LastSeenAtUtc), UpdatedAtUtc = @AsOfUtc
     WHERE Status = N'Active' AND EventType = @EventType
       AND LastSeenAtUtc < DATEADD(SECOND, -@AfterSeconds, @AsOfUtc);
    SELECT CAST(@@ROWCOUNT AS int) AS RowsResolved;
END;
