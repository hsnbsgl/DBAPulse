CREATE OR ALTER PROCEDURE dbo.usp_Anomalies_Overview
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SUM(CASE WHEN Status = N'Active' THEN 1 ELSE 0 END) ActiveAnomalyCount, SUM(CASE WHEN Status = N'Active' AND Severity = N'Critical' THEN 1 ELSE 0 END) ActiveCriticalCount, SUM(CASE WHEN Status = N'Active' AND Severity = N'Warning' THEN 1 ELSE 0 END) ActiveWarningCount, SUM(CASE WHEN Status = N'Resolved' THEN 1 ELSE 0 END) ResolvedAnomalyCount, (SELECT COUNT(*) FROM dbo.Baselines WHERE Status = N'Usable') UsableBaselineCount, (SELECT COUNT(*) FROM dbo.Baselines WHERE Status = N'InsufficientData') InsufficientBaselineCount, COUNT(DISTINCT CASE WHEN Status = N'Active' THEN CONCAT(ServerId, N':', ISNULL(DatabaseId, 0), N':', ISNULL(EntityKey, N'')) END) EntitiesWithAnomalies FROM dbo.AnomalyFindings;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Anomalies_List
    @MetricType nvarchar(64) = NULL, @Severity nvarchar(20) = NULL, @Status nvarchar(20) = NULL, @ServerId int = NULL, @DatabaseId int = NULL, @FromUtc datetime2(3) = NULL, @ToUtc datetime2(3) = NULL, @Page int = 1, @PageSize int = 50
AS
BEGIN
    SET NOCOUNT ON; SET @Page = CASE WHEN @Page < 1 THEN 1 ELSE @Page END; SET @PageSize = CASE WHEN @PageSize < 1 THEN 1 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SELECT f.Id,f.MetricType,s.ServerName,d.DatabaseName,f.EntityKey,f.ObservedAtUtc,f.ObservedValue,f.BaselineMedian,f.BaselineP95,f.DeviationRatio,f.ModifiedZScore,f.BaselineScope,f.SampleCount,f.Severity,f.Status,f.ExplanationCode,f.StartedAtUtc,f.LastSeenAtUtc FROM dbo.AnomalyFindings f JOIN dbo.Servers s ON s.Id=f.ServerId LEFT JOIN dbo.Databases d ON d.Id=f.DatabaseId WHERE (@MetricType IS NULL OR f.MetricType=@MetricType) AND (@Severity IS NULL OR f.Severity=@Severity) AND (@Status IS NULL OR f.Status=@Status) AND (@ServerId IS NULL OR f.ServerId=@ServerId) AND (@DatabaseId IS NULL OR f.DatabaseId=@DatabaseId) AND (@FromUtc IS NULL OR f.ObservedAtUtc>=@FromUtc) AND (@ToUtc IS NULL OR f.ObservedAtUtc<=@ToUtc) ORDER BY f.ObservedAtUtc DESC OFFSET (@Page-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    SELECT COUNT(*) TotalCount FROM dbo.AnomalyFindings f WHERE (@MetricType IS NULL OR f.MetricType=@MetricType) AND (@Severity IS NULL OR f.Severity=@Severity) AND (@Status IS NULL OR f.Status=@Status) AND (@ServerId IS NULL OR f.ServerId=@ServerId) AND (@DatabaseId IS NULL OR f.DatabaseId=@DatabaseId) AND (@FromUtc IS NULL OR f.ObservedAtUtc>=@FromUtc) AND (@ToUtc IS NULL OR f.ObservedAtUtc<=@ToUtc);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Anomaly_Detail @Id bigint AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.Id,f.MetricType,s.ServerName,d.DatabaseName,f.EntityKey,f.ObservedAtUtc,f.ObservedValue,f.BaselineMedian,f.BaselineP95,f.BaselineP99,f.BaselineMad,f.DeviationRatio,f.ModifiedZScore,f.BaselineScope,f.SampleCount,b.WindowDays,f.Severity,f.Status,f.ExplanationCode,f.StartedAtUtc,f.LastSeenAtUtc,f.EndedAtUtc,f.ObservationCount,f.SourceEntityId,f.Fingerprint FROM dbo.AnomalyFindings f JOIN dbo.Servers s ON s.Id=f.ServerId LEFT JOIN dbo.Databases d ON d.Id=f.DatabaseId OUTER APPLY (SELECT TOP(1) WindowDays FROM dbo.Baselines WHERE MetricType=f.MetricType AND ServerId=f.ServerId AND (DatabaseId=f.DatabaseId OR (DatabaseId IS NULL AND f.DatabaseId IS NULL)) ORDER BY CalculatedAtUtc DESC) b WHERE f.Id=@Id;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Baselines_List @MetricType nvarchar(64)=NULL, @Status nvarchar(24)=NULL, @ServerId int=NULL, @DatabaseId int=NULL, @Page int=1, @PageSize int=50 AS
BEGIN
    SET NOCOUNT ON; SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
    SELECT b.Id,b.MetricType,s.ServerName,d.DatabaseName,b.EntityKey,b.DayOfWeek,b.HourOfDay,b.WindowDays,b.SampleCount,b.MedianValue,b.P90Value,b.P95Value,b.P99Value,b.MadValue,b.MeanValue,b.StdDevValue,b.BaselineScope,b.CalculatedAtUtc,b.Status FROM dbo.Baselines b JOIN dbo.Servers s ON s.Id=b.ServerId LEFT JOIN dbo.Databases d ON d.Id=b.DatabaseId WHERE (@MetricType IS NULL OR b.MetricType=@MetricType) AND (@Status IS NULL OR b.Status=@Status) AND (@ServerId IS NULL OR b.ServerId=@ServerId) AND (@DatabaseId IS NULL OR b.DatabaseId=@DatabaseId) ORDER BY b.CalculatedAtUtc DESC OFFSET (@Page-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    SELECT COUNT(*) TotalCount FROM dbo.Baselines b WHERE (@MetricType IS NULL OR b.MetricType=@MetricType) AND (@Status IS NULL OR b.Status=@Status) AND (@ServerId IS NULL OR b.ServerId=@ServerId) AND (@DatabaseId IS NULL OR b.DatabaseId=@DatabaseId);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Baseline_Detail @Id bigint AS SELECT b.Id,b.MetricType,s.ServerName,d.DatabaseName,b.EntityKey,b.DayOfWeek,b.HourOfDay,b.WindowDays,b.SampleCount,b.MedianValue,b.P90Value,b.P95Value,b.P99Value,b.MadValue,b.MeanValue,b.StdDevValue,b.BaselineScope,b.CalculatedAtUtc,b.Status FROM dbo.Baselines b JOIN dbo.Servers s ON s.Id=b.ServerId LEFT JOIN dbo.Databases d ON d.Id=b.DatabaseId WHERE b.Id=@Id;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Baselines_Evaluation_List AS
BEGIN
    SET NOCOUNT ON;
    SELECT MetricType,ServerId,DatabaseId,EntityKey,DayOfWeek,HourOfDay,WindowDays,SampleCount,MedianValue,P75Value,P90Value,P95Value,P99Value,MeanValue,StdDevValue,MadValue,MinValue,MaxValue,CalculatedAtUtc,ValidFromUtc,Status,BaselineScope FROM dbo.Baselines;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_AnomalyPolicies_List AS
BEGIN
    SET NOCOUNT ON;
    SELECT MetricType,WarningPercentile,CriticalPercentile,WarningModifiedZ,CriticalModifiedZ,MinObservedValue,IsEnabled FROM dbo.AnomalyPolicies;
END;
