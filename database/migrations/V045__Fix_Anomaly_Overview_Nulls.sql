CREATE OR ALTER PROCEDURE dbo.usp_Anomalies_Overview
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        COALESCE(SUM(CASE WHEN Status = N'Active' THEN 1 ELSE 0 END), 0) ActiveAnomalyCount,
        COALESCE(SUM(CASE WHEN Status = N'Active' AND Severity = N'Critical' THEN 1 ELSE 0 END), 0) ActiveCriticalCount,
        COALESCE(SUM(CASE WHEN Status = N'Active' AND Severity = N'Warning' THEN 1 ELSE 0 END), 0) ActiveWarningCount,
        COALESCE(SUM(CASE WHEN Status = N'Resolved' THEN 1 ELSE 0 END), 0) ResolvedAnomalyCount,
        (SELECT COUNT(*) FROM dbo.Baselines WHERE Status = N'Usable') UsableBaselineCount,
        (SELECT COUNT(*) FROM dbo.Baselines WHERE Status = N'InsufficientData') InsufficientBaselineCount,
        COUNT(DISTINCT CASE WHEN Status = N'Active' THEN CONCAT(ServerId, N':', ISNULL(DatabaseId, 0), N':', ISNULL(EntityKey, N'')) END) EntitiesWithAnomalies
    FROM dbo.AnomalyFindings;
END;
GO
