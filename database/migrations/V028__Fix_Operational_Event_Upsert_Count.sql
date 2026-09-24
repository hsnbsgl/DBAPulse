CREATE OR ALTER PROCEDURE dbo.usp_OperationalEvents_Upsert
    @Rows dbo.OperationalEventInputType READONLY,
    @AsOfUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    DECLARE @Updated int = 0, @Inserted int = 0;
    BEGIN TRANSACTION;
    UPDATE e
       SET e.LastSeenAtUtc = CASE WHEN r.LastSeenAtUtc > e.LastSeenAtUtc THEN r.LastSeenAtUtc ELSE e.LastSeenAtUtc END,
           e.DurationMs = DATEDIFF_BIG(MILLISECOND, e.StartedAtUtc, CASE WHEN r.LastSeenAtUtc > e.LastSeenAtUtc THEN r.LastSeenAtUtc ELSE e.LastSeenAtUtc END),
           e.ObservationCount = e.ObservationCount + r.ObservationIncrement,
           e.AffectedSessionCount = COALESCE(r.AffectedSessionCount, e.AffectedSessionCount),
           e.Severity = r.Severity, e.Status = N'Active', e.EndedAtUtc = NULL, e.UpdatedAtUtc = @AsOfUtc
    FROM dbo.OperationalEvents AS e WITH (UPDLOCK)
    INNER JOIN @Rows AS r ON r.Fingerprint = e.Fingerprint AND r.EventType = e.EventType
    WHERE e.Status = N'Active' AND r.Status = N'Active';
    SET @Updated = @@ROWCOUNT;

    INSERT dbo.OperationalEvents (EventType, ServerId, DatabaseId, Fingerprint, StartedAtUtc, LastSeenAtUtc, DurationMs, Status, Severity, ObservationCount, AffectedSessionCount, Title, Summary, SourceEntityId, CreatedAtUtc, UpdatedAtUtc, AdditionalData)
    SELECT r.EventType, r.ServerId, r.DatabaseId, r.Fingerprint, r.StartedAtUtc, r.LastSeenAtUtc, r.DurationMs, r.Status, r.Severity, r.ObservationIncrement, r.AffectedSessionCount, r.Title, r.Summary, r.SourceEntityId, @AsOfUtc, @AsOfUtc, r.AdditionalData
    FROM @Rows AS r
    WHERE NOT EXISTS (SELECT 1 FROM dbo.OperationalEvents AS e WITH (UPDLOCK, HOLDLOCK) WHERE e.EventType = r.EventType AND e.Fingerprint = r.Fingerprint AND (e.Status = N'Active' OR r.EventType = N'Deadlock'));
    SET @Inserted = @@ROWCOUNT;
    COMMIT TRANSACTION;
    SELECT @Updated + @Inserted AS RowsAffected;
END;
