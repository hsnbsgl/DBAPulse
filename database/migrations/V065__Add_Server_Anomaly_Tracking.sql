IF COL_LENGTH(N'dbo.Servers', N'AnomalyTrackingEnabled') IS NULL
    ALTER TABLE dbo.Servers ADD AnomalyTrackingEnabled bit NOT NULL CONSTRAINT DF_Servers_AnomalyTrackingEnabled DEFAULT (1);
GO

CREATE OR ALTER PROCEDURE dbo.usp_Management_Overview AS
BEGIN
 SET NOCOUNT ON;
 SELECT (SELECT COUNT(*) FROM dbo.Servers WHERE IsActive=1) ServerCount,(SELECT COUNT(*) FROM dbo.Databases WHERE IsActive=1) DatabaseCount,
 (SELECT COUNT(DISTINCT CONCAT(e.ServerId,N':',ISNULL(e.DatabaseId,0))) FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.Status=N'Active' AND e.Severity=N'Critical' AND NOT (e.EventType IN(N'PerformanceAnomaly',N'JobDurationAnomaly',N'BackupDurationAnomaly',N'GrowthAnomaly') AND s.AnomalyTrackingEnabled=0)) CriticalEntityCount,
 (SELECT COUNT(DISTINCT CONCAT(e.ServerId,N':',ISNULL(e.DatabaseId,0))) FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.Status=N'Active' AND e.Severity=N'Warning' AND NOT (e.EventType IN(N'PerformanceAnomaly',N'JobDurationAnomaly',N'BackupDurationAnomaly',N'GrowthAnomaly') AND s.AnomalyTrackingEnabled=0)) WarningEntityCount,0 AttentionEntityCount,
 (SELECT COUNT(*) FROM dbo.Databases d WHERE d.IsActive=1 AND NOT EXISTS(SELECT 1 FROM dbo.DatabaseSnapshots x WHERE x.DatabaseId=d.Id AND x.CollectedAtUtc>=DATEADD(HOUR,-3,SYSUTCDATETIME()))) UnknownEntityCount,
 (SELECT COUNT(*) FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.Status=N'Active' AND NOT (e.EventType IN(N'PerformanceAnomaly',N'JobDurationAnomaly',N'BackupDurationAnomaly',N'GrowthAnomaly') AND s.AnomalyTrackingEnabled=0)) ActiveOperationalEvents,
 (SELECT COUNT(*) FROM dbo.AnomalyFindings a JOIN dbo.Servers s ON s.Id=a.ServerId WHERE s.AnomalyTrackingEnabled=1 AND a.Status=N'Active') ActiveAnomalies,
 (SELECT COUNT(*) FROM dbo.ManagementCorrelationGroups g JOIN dbo.Servers s ON s.Id=g.ServerId WHERE s.AnomalyTrackingEnabled=1 AND g.Status=N'Active') RelatedSignalGroups,
 (SELECT COUNT(*) FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.Severity=N'Critical' AND e.StartedAtUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME()) AND NOT (e.EventType IN(N'PerformanceAnomaly',N'JobDurationAnomaly',N'BackupDurationAnomaly',N'GrowthAnomaly') AND s.AnomalyTrackingEnabled=0))+(SELECT COUNT(*) FROM dbo.AnomalyFindings a JOIN dbo.Servers s ON s.Id=a.ServerId WHERE s.AnomalyTrackingEnabled=1 AND a.Severity=N'Critical' AND a.StartedAtUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME())) NewCritical24h,
 (SELECT COUNT(*) FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.Status=N'Resolved' AND e.EndedAtUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME()) AND NOT (e.EventType IN(N'PerformanceAnomaly',N'JobDurationAnomaly',N'BackupDurationAnomaly',N'GrowthAnomaly') AND s.AnomalyTrackingEnabled=0))+(SELECT COUNT(*) FROM dbo.AnomalyFindings a JOIN dbo.Servers s ON s.Id=a.ServerId WHERE s.AnomalyTrackingEnabled=1 AND a.Status=N'Resolved' AND a.EndedAtUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME())) Resolved24h;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Management_NeedsAttention @Severity nvarchar(20)=NULL,@ServerId int=NULL,@DatabaseId int=NULL,@Domain nvarchar(32)=NULL,@Page int=1,@PageSize int=50 AS
BEGIN
 SET NOCOUNT ON; SET @Page=CASE WHEN @Page<1 THEN 1 ELSE @Page END; SET @PageSize=CASE WHEN @PageSize BETWEEN 1 AND 100 THEN @PageSize ELSE 50 END;
 ;WITH x AS
 (SELECT e.Id,e.Severity,N'Server' EntityType,e.ServerId,e.DatabaseId,s.ServerName,d.DatabaseName,
 CASE WHEN e.EventType IN(N'Blocking',N'LongRunning',N'Deadlock') THEN N'Performance' WHEN e.EventType=N'BackupProtection' THEN N'Protection' WHEN e.EventType=N'AlwaysOnHealth' THEN N'Availability' ELSE N'Operations' END Domain,
 e.Title Issue,CASE WHEN e.EventType=N'BackupProtection' THEN N'BACKUP_CRITICAL' WHEN e.EventType=N'AlwaysOnHealth' THEN N'AG_UNHEALTHY' ELSE N'ACTIVE_CRITICAL_EVENT' END ExplanationCode,e.StartedAtUtc,e.LastSeenAtUtc,e.Status,e.SourceEntityId
 FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId LEFT JOIN dbo.Databases d ON d.Id=e.DatabaseId WHERE e.Status=N'Active' AND NOT (e.EventType IN(N'PerformanceAnomaly',N'JobDurationAnomaly',N'BackupDurationAnomaly',N'GrowthAnomaly') AND s.AnomalyTrackingEnabled=0)
 UNION ALL SELECT a.Id,a.Severity,N'Database',a.ServerId,a.DatabaseId,s.ServerName,d.DatabaseName,N'Anomaly',CONCAT(a.MetricType,N' anomaly'),a.ExplanationCode,a.StartedAtUtc,a.LastSeenAtUtc,a.Status,a.SourceEntityId
 FROM dbo.AnomalyFindings a JOIN dbo.Servers s ON s.Id=a.ServerId LEFT JOIN dbo.Databases d ON d.Id=a.DatabaseId WHERE a.Status=N'Active' AND s.AnomalyTrackingEnabled=1)
 SELECT x.Id,x.Severity,x.EntityType,x.ServerId,x.DatabaseId,x.ServerName,x.DatabaseName,x.Domain,x.Issue,x.ExplanationCode,x.StartedAtUtc,x.LastSeenAtUtc,0 RelatedSignalCount,x.Status,x.SourceEntityId
 FROM x WHERE (@Severity IS NULL OR x.Severity=@Severity) AND (@ServerId IS NULL OR x.ServerId=@ServerId) AND (@DatabaseId IS NULL OR x.DatabaseId=@DatabaseId) AND (@Domain IS NULL OR x.Domain=@Domain)
 ORDER BY CASE x.Severity WHEN N'Critical' THEN 1 WHEN N'Warning' THEN 2 ELSE 3 END,x.LastSeenAtUtc DESC OFFSET (@Page-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
 SELECT COUNT(*) TotalCount FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.Status=N'Active' AND NOT (e.EventType IN(N'PerformanceAnomaly',N'JobDurationAnomaly',N'BackupDurationAnomaly',N'GrowthAnomaly') AND s.AnomalyTrackingEnabled=0);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Management_Health @ServerId int=NULL,@DatabaseId int=NULL AS
BEGIN
 SET NOCOUNT ON;
 ;WITH entities AS (SELECT s.Id ServerId,CAST(NULL AS int) DatabaseId,s.ServerName,CAST(NULL AS nvarchar(256)) DatabaseName,s.AnomalyTrackingEnabled FROM dbo.Servers s WHERE s.IsActive=1 UNION ALL SELECT d.ServerId,d.Id,s.ServerName,d.DatabaseName,s.AnomalyTrackingEnabled FROM dbo.Databases d JOIN dbo.Servers s ON s.Id=d.ServerId WHERE d.IsActive=1),
 risks AS (SELECT e.ServerId,e.DatabaseId,e.Severity,CASE WHEN e.EventType IN(N'Blocking',N'LongRunning',N'Deadlock') THEN N'Performance' WHEN e.EventType=N'BackupProtection' THEN N'Protection' WHEN e.EventType=N'AlwaysOnHealth' THEN N'Availability' ELSE N'Operations' END Domain FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId WHERE e.Status=N'Active' AND NOT (e.EventType IN(N'PerformanceAnomaly',N'JobDurationAnomaly',N'BackupDurationAnomaly',N'GrowthAnomaly') AND s.AnomalyTrackingEnabled=0) UNION ALL SELECT a.ServerId,a.DatabaseId,a.Severity,N'Anomaly' FROM dbo.AnomalyFindings a JOIN dbo.Servers s ON s.Id=a.ServerId WHERE a.Status=N'Active' AND s.AnomalyTrackingEnabled=1),
 agg AS (SELECT en.*,MAX(CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END) Level,MAX(CASE WHEN r.Domain=N'Performance' THEN CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END ELSE 0 END) Perf,MAX(CASE WHEN r.Domain=N'Protection' THEN CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END ELSE 0 END) Protect,MAX(CASE WHEN r.Domain=N'Availability' THEN CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END ELSE 0 END) Avail,MAX(CASE WHEN r.Domain=N'Anomaly' THEN CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END ELSE 0 END) Anomaly FROM entities en LEFT JOIN risks r ON r.ServerId=en.ServerId AND (r.DatabaseId=en.DatabaseId OR r.DatabaseId IS NULL) WHERE (@ServerId IS NULL OR en.ServerId=@ServerId) AND (@DatabaseId IS NULL OR en.DatabaseId=@DatabaseId) GROUP BY en.ServerId,en.DatabaseId,en.ServerName,en.DatabaseName,en.AnomalyTrackingEnabled)
 SELECT CASE WHEN DatabaseId IS NULL THEN N'Server' ELSE N'Database' END EntityType,CASE WHEN Level=3 THEN N'Critical' WHEN Level=2 THEN N'Warning' WHEN DatabaseId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.DatabaseSnapshots x WHERE x.DatabaseId=agg.DatabaseId AND x.CollectedAtUtc>=DATEADD(HOUR,-3,SYSUTCDATETIME())) THEN N'Unknown' ELSE N'Healthy' END OverallStatus,
 CASE WHEN Perf=3 THEN N'Critical' WHEN Perf=2 THEN N'Warning' ELSE N'Healthy' END PerformanceStatus,CASE WHEN Protect=3 THEN N'Critical' WHEN Protect=2 THEN N'Warning' ELSE N'Healthy' END ProtectionStatus,CASE WHEN Avail=3 THEN N'Critical' WHEN Avail=2 THEN N'Warning' ELSE N'Healthy' END AvailabilityStatus,N'Unknown' CapacityStatus,CASE WHEN AnomalyTrackingEnabled=0 THEN N'Disabled' WHEN Anomaly=3 THEN N'Critical' WHEN Anomaly=2 THEN N'Warning' ELSE N'Healthy' END AnomalyStatus,
 CASE WHEN DatabaseId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.DatabaseSnapshots x WHERE x.DatabaseId=agg.DatabaseId AND x.CollectedAtUtc>=DATEADD(HOUR,-3,SYSUTCDATETIME())) THEN N'Unknown' ELSE N'Fresh' END FreshnessStatus,agg.ServerId,agg.DatabaseId,agg.ServerName,agg.DatabaseName,0 ActiveCriticalCount,0 ActiveWarningCount,0 ActiveAttentionCount,0 RelatedSignalCount
 FROM agg;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Anomalies_Overview AS
BEGIN
 SET NOCOUNT ON;
 SELECT COALESCE(SUM(CASE WHEN a.Status=N'Active' THEN 1 ELSE 0 END),0) ActiveAnomalyCount,COALESCE(SUM(CASE WHEN a.Status=N'Active' AND a.Severity=N'Critical' THEN 1 ELSE 0 END),0) ActiveCriticalCount,COALESCE(SUM(CASE WHEN a.Status=N'Active' AND a.Severity=N'Warning' THEN 1 ELSE 0 END),0) ActiveWarningCount,COALESCE(SUM(CASE WHEN a.Status=N'Resolved' THEN 1 ELSE 0 END),0) ResolvedAnomalyCount,(SELECT COUNT(*) FROM dbo.Baselines b JOIN dbo.Servers s ON s.Id=b.ServerId WHERE s.AnomalyTrackingEnabled=1 AND b.Status=N'Usable') UsableBaselineCount,(SELECT COUNT(*) FROM dbo.Baselines b JOIN dbo.Servers s ON s.Id=b.ServerId WHERE s.AnomalyTrackingEnabled=1 AND b.Status=N'InsufficientData') InsufficientBaselineCount,COUNT(DISTINCT CASE WHEN a.Status=N'Active' THEN CONCAT(a.ServerId,N':',ISNULL(a.DatabaseId,0),N':',ISNULL(a.EntityKey,N'')) END) EntitiesWithAnomalies FROM dbo.AnomalyFindings a JOIN dbo.Servers s ON s.Id=a.ServerId WHERE s.AnomalyTrackingEnabled=1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Anomalies_List
    @MetricType nvarchar(64)=NULL,@Severity nvarchar(20)=NULL,@Status nvarchar(20)=NULL,@ServerId int=NULL,@DatabaseId int=NULL,@FromUtc datetime2(3)=NULL,@ToUtc datetime2(3)=NULL,@Page int=1,@PageSize int=50
AS
BEGIN
 SET NOCOUNT ON; SET @Page=CASE WHEN @Page<1 THEN 1 ELSE @Page END; SET @PageSize=CASE WHEN @PageSize<1 THEN 1 WHEN @PageSize>100 THEN 100 ELSE @PageSize END;
 SELECT f.Id,f.MetricType,s.ServerName,d.DatabaseName,f.EntityKey,f.ObservedAtUtc,f.ObservedValue,f.BaselineMedian,f.BaselineP95,f.DeviationRatio,f.ModifiedZScore,f.BaselineScope,f.SampleCount,f.Severity,f.Status,f.ExplanationCode,f.StartedAtUtc,f.LastSeenAtUtc FROM dbo.AnomalyFindings f JOIN dbo.Servers s ON s.Id=f.ServerId LEFT JOIN dbo.Databases d ON d.Id=f.DatabaseId WHERE s.AnomalyTrackingEnabled=1 AND (@MetricType IS NULL OR f.MetricType=@MetricType) AND (@Severity IS NULL OR f.Severity=@Severity) AND (@Status IS NULL OR f.Status=@Status) AND (@ServerId IS NULL OR f.ServerId=@ServerId) AND (@DatabaseId IS NULL OR f.DatabaseId=@DatabaseId) AND (@FromUtc IS NULL OR f.ObservedAtUtc>=@FromUtc) AND (@ToUtc IS NULL OR f.ObservedAtUtc<=@ToUtc) ORDER BY f.ObservedAtUtc DESC OFFSET (@Page-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
 SELECT COUNT(*) TotalCount FROM dbo.AnomalyFindings f JOIN dbo.Servers s ON s.Id=f.ServerId WHERE s.AnomalyTrackingEnabled=1 AND (@MetricType IS NULL OR f.MetricType=@MetricType) AND (@Severity IS NULL OR f.Severity=@Severity) AND (@Status IS NULL OR f.Status=@Status) AND (@ServerId IS NULL OR f.ServerId=@ServerId) AND (@DatabaseId IS NULL OR f.DatabaseId=@DatabaseId) AND (@FromUtc IS NULL OR f.ObservedAtUtc>=@FromUtc) AND (@ToUtc IS NULL OR f.ObservedAtUtc<=@ToUtc);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Anomaly_Detail @Id bigint AS
BEGIN
 SET NOCOUNT ON;
 SELECT f.Id,f.MetricType,s.ServerName,d.DatabaseName,f.EntityKey,f.ObservedAtUtc,f.ObservedValue,f.BaselineMedian,f.BaselineP95,f.BaselineP99,f.BaselineMad,f.DeviationRatio,f.ModifiedZScore,f.BaselineScope,f.SampleCount,b.WindowDays,f.Severity,f.Status,f.ExplanationCode,f.StartedAtUtc,f.LastSeenAtUtc,f.EndedAtUtc,f.ObservationCount,f.SourceEntityId,f.Fingerprint FROM dbo.AnomalyFindings f JOIN dbo.Servers s ON s.Id=f.ServerId LEFT JOIN dbo.Databases d ON d.Id=f.DatabaseId OUTER APPLY (SELECT TOP(1) WindowDays FROM dbo.Baselines WHERE MetricType=f.MetricType AND ServerId=f.ServerId AND (DatabaseId=f.DatabaseId OR (DatabaseId IS NULL AND f.DatabaseId IS NULL)) ORDER BY CalculatedAtUtc DESC) b WHERE f.Id=@Id AND s.AnomalyTrackingEnabled=1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Baselines_Evaluation_List AS
BEGIN
 SET NOCOUNT ON;
 SELECT b.MetricType,b.ServerId,b.DatabaseId,b.EntityKey,b.DayOfWeek,b.HourOfDay,b.WindowDays,b.SampleCount,b.MedianValue,b.P75Value,b.P90Value,b.P95Value,b.P99Value,b.MeanValue,b.StdDevValue,b.MadValue,b.MinValue,b.MaxValue,b.CalculatedAtUtc,b.ValidFromUtc,b.Status,b.BaselineScope FROM dbo.Baselines b JOIN dbo.Servers s ON s.Id=b.ServerId WHERE s.AnomalyTrackingEnabled=1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Server_Detail @ServerId int AS
BEGIN
 SET NOCOUNT ON;
 SELECT s.Id AS ServerId,s.ServerName,s.InstanceName,s.SqlVersion,s.Edition,s.TimeZoneId,s.LastSeenAtUtc,s.AnomalyTrackingEnabled,COUNT(d.Id) AS DatabaseCount
 FROM dbo.Servers s LEFT JOIN dbo.Databases d ON d.ServerId=s.Id AND d.IsActive=1 WHERE s.Id=@ServerId
 GROUP BY s.Id,s.ServerName,s.InstanceName,s.SqlVersion,s.Edition,s.TimeZoneId,s.LastSeenAtUtc,s.AnomalyTrackingEnabled;
 SELECT d.Id AS DatabaseId,d.DatabaseName,d.DatabaseStatus,d.RecoveryModel,d.LastSeenAtUtc FROM dbo.Databases d WHERE d.ServerId=@ServerId AND d.IsActive=1 ORDER BY d.DatabaseName;
END;
GO
