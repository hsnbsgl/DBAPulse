CREATE OR ALTER PROCEDURE dbo.usp_DeadlockEvents_Insert
    @Rows dbo.DeadlockEventInputType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH Deduplicated AS
    (
        SELECT r.*, ROW_NUMBER() OVER (PARTITION BY r.DeadlockHash ORDER BY r.OccurredAtUtc, r.CollectedAtUtc) AS rn
        FROM @Rows AS r
    )
    INSERT dbo.DeadlockEvents (ServerId, DatabaseId, OccurredAtUtc, VictimProcessId, VictimSessionId, ProcessCount, DeadlockHash, DeadlockXml, CollectedAtUtc)
    SELECT r.ServerId, r.DatabaseId, r.OccurredAtUtc, r.VictimProcessId, r.VictimSessionId, r.ProcessCount, r.DeadlockHash, r.DeadlockXml, r.CollectedAtUtc
    FROM Deduplicated AS r
    WHERE r.rn = 1 AND NOT EXISTS (SELECT 1 FROM dbo.DeadlockEvents AS d WHERE d.DeadlockHash = r.DeadlockHash);
    SELECT CAST(@@ROWCOUNT AS int) AS RowsInserted;
END;
