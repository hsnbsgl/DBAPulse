CREATE OR ALTER PROCEDURE dbo.usp_Management_Overview AS
BEGIN
 SET NOCOUNT ON;
 SELECT (SELECT COUNT(*) FROM dbo.Servers WHERE IsActive=1) ServerCount,(SELECT COUNT(*) FROM dbo.Databases WHERE IsActive=1) DatabaseCount,
 (SELECT COUNT(DISTINCT CONCAT(ServerId,N':',ISNULL(DatabaseId,0))) FROM dbo.OperationalEvents WHERE Status=N'Active' AND Severity=N'Critical') CriticalEntityCount,
 (SELECT COUNT(DISTINCT CONCAT(ServerId,N':',ISNULL(DatabaseId,0))) FROM dbo.OperationalEvents WHERE Status=N'Active' AND Severity=N'Warning') WarningEntityCount,0 AttentionEntityCount,
 (SELECT COUNT(*) FROM dbo.Databases d WHERE d.IsActive=1 AND NOT EXISTS(SELECT 1 FROM dbo.DatabaseSnapshots x WHERE x.DatabaseId=d.Id AND x.CollectedAtUtc>=DATEADD(HOUR,-3,SYSUTCDATETIME()))) UnknownEntityCount,
 (SELECT COUNT(*) FROM dbo.OperationalEvents WHERE Status=N'Active') ActiveOperationalEvents,(SELECT COUNT(*) FROM dbo.AnomalyFindings WHERE Status=N'Active') ActiveAnomalies,
 (SELECT COUNT(*) FROM dbo.ManagementCorrelationGroups WHERE Status=N'Active') RelatedSignalGroups,
 (SELECT COUNT(*) FROM dbo.OperationalEvents WHERE Severity=N'Critical' AND StartedAtUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME()))+(SELECT COUNT(*) FROM dbo.AnomalyFindings WHERE Severity=N'Critical' AND StartedAtUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME())) NewCritical24h,
 (SELECT COUNT(*) FROM dbo.OperationalEvents WHERE Status=N'Resolved' AND EndedAtUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME()))+(SELECT COUNT(*) FROM dbo.AnomalyFindings WHERE Status=N'Resolved' AND EndedAtUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME())) Resolved24h;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Management_NeedsAttention @Severity nvarchar(20)=NULL,@ServerId int=NULL,@DatabaseId int=NULL,@Domain nvarchar(32)=NULL,@Page int=1,@PageSize int=50 AS
BEGIN
 SET NOCOUNT ON; SET @Page=CASE WHEN @Page<1 THEN 1 ELSE @Page END; SET @PageSize=CASE WHEN @PageSize BETWEEN 1 AND 100 THEN @PageSize ELSE 50 END;
 ;WITH x AS
 (SELECT e.Id,e.Severity,N'Server' EntityType,e.ServerId,e.DatabaseId,s.ServerName,d.DatabaseName,
 CASE WHEN e.EventType IN(N'Blocking',N'LongRunning',N'Deadlock') THEN N'Performance' WHEN e.EventType=N'BackupProtection' THEN N'Protection' WHEN e.EventType=N'AlwaysOnHealth' THEN N'Availability' ELSE N'Operations' END Domain,
 e.Title Issue,CASE WHEN e.EventType=N'BackupProtection' THEN N'BACKUP_CRITICAL' WHEN e.EventType=N'AlwaysOnHealth' THEN N'AG_UNHEALTHY' ELSE N'ACTIVE_CRITICAL_EVENT' END ExplanationCode,e.StartedAtUtc,e.LastSeenAtUtc,e.Status,e.SourceEntityId
 FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId LEFT JOIN dbo.Databases d ON d.Id=e.DatabaseId WHERE e.Status=N'Active'
 UNION ALL SELECT a.Id,a.Severity,N'Database',a.ServerId,a.DatabaseId,s.ServerName,d.DatabaseName,N'Anomaly',CONCAT(a.MetricType,N' anomaly'),a.ExplanationCode,a.StartedAtUtc,a.LastSeenAtUtc,a.Status,a.SourceEntityId
 FROM dbo.AnomalyFindings a JOIN dbo.Servers s ON s.Id=a.ServerId LEFT JOIN dbo.Databases d ON d.Id=a.DatabaseId WHERE a.Status=N'Active')
 SELECT x.Id,x.Severity,x.EntityType,x.ServerId,x.DatabaseId,x.ServerName,x.DatabaseName,x.Domain,x.Issue,x.ExplanationCode,x.StartedAtUtc,x.LastSeenAtUtc,0 RelatedSignalCount,x.Status,x.SourceEntityId
 FROM x WHERE (@Severity IS NULL OR x.Severity=@Severity) AND (@ServerId IS NULL OR x.ServerId=@ServerId) AND (@DatabaseId IS NULL OR x.DatabaseId=@DatabaseId) AND (@Domain IS NULL OR x.Domain=@Domain)
 ORDER BY CASE x.Severity WHEN N'Critical' THEN 1 WHEN N'Warning' THEN 2 ELSE 3 END,x.LastSeenAtUtc DESC OFFSET (@Page-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
 SELECT COUNT(*) TotalCount FROM dbo.OperationalEvents WHERE Status=N'Active';
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Management_Health @ServerId int=NULL,@DatabaseId int=NULL AS
BEGIN
 SET NOCOUNT ON;
 ;WITH entities AS (SELECT s.Id ServerId,CAST(NULL AS int) DatabaseId,s.ServerName,CAST(NULL AS nvarchar(256)) DatabaseName FROM dbo.Servers s WHERE s.IsActive=1 UNION ALL SELECT d.ServerId,d.Id,s.ServerName,d.DatabaseName FROM dbo.Databases d JOIN dbo.Servers s ON s.Id=d.ServerId WHERE d.IsActive=1),
 risks AS (SELECT e.ServerId,e.DatabaseId,e.Severity,CASE WHEN e.EventType IN(N'Blocking',N'LongRunning',N'Deadlock') THEN N'Performance' WHEN e.EventType=N'BackupProtection' THEN N'Protection' WHEN e.EventType=N'AlwaysOnHealth' THEN N'Availability' ELSE N'Operations' END Domain FROM dbo.OperationalEvents e WHERE e.Status=N'Active' UNION ALL SELECT a.ServerId,a.DatabaseId,a.Severity,N'Anomaly' FROM dbo.AnomalyFindings a WHERE a.Status=N'Active'),
 agg AS (SELECT en.*,MAX(CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END) Level,MAX(CASE WHEN r.Domain=N'Performance' THEN CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END ELSE 0 END) Perf,MAX(CASE WHEN r.Domain=N'Protection' THEN CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END ELSE 0 END) Protect,MAX(CASE WHEN r.Domain=N'Availability' THEN CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END ELSE 0 END) Avail,MAX(CASE WHEN r.Domain=N'Anomaly' THEN CASE WHEN r.Severity=N'Critical' THEN 3 WHEN r.Severity=N'Warning' THEN 2 ELSE 0 END ELSE 0 END) Anomaly FROM entities en LEFT JOIN risks r ON r.ServerId=en.ServerId AND (r.DatabaseId=en.DatabaseId OR r.DatabaseId IS NULL) WHERE (@ServerId IS NULL OR en.ServerId=@ServerId) AND (@DatabaseId IS NULL OR en.DatabaseId=@DatabaseId) GROUP BY en.ServerId,en.DatabaseId,en.ServerName,en.DatabaseName)
 SELECT CASE WHEN DatabaseId IS NULL THEN N'Server' ELSE N'Database' END EntityType,CASE WHEN Level=3 THEN N'Critical' WHEN Level=2 THEN N'Warning' WHEN DatabaseId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.DatabaseSnapshots x WHERE x.DatabaseId=agg.DatabaseId AND x.CollectedAtUtc>=DATEADD(HOUR,-3,SYSUTCDATETIME())) THEN N'Unknown' ELSE N'Healthy' END OverallStatus,
 CASE WHEN Perf=3 THEN N'Critical' WHEN Perf=2 THEN N'Warning' ELSE N'Healthy' END PerformanceStatus,CASE WHEN Protect=3 THEN N'Critical' WHEN Protect=2 THEN N'Warning' ELSE N'Healthy' END ProtectionStatus,CASE WHEN Avail=3 THEN N'Critical' WHEN Avail=2 THEN N'Warning' ELSE N'Healthy' END AvailabilityStatus, N'Unknown' CapacityStatus,CASE WHEN Anomaly=3 THEN N'Critical' WHEN Anomaly=2 THEN N'Warning' ELSE N'Healthy' END AnomalyStatus,
 CASE WHEN DatabaseId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.DatabaseSnapshots x WHERE x.DatabaseId=agg.DatabaseId AND x.CollectedAtUtc>=DATEADD(HOUR,-3,SYSUTCDATETIME())) THEN N'Unknown' ELSE N'Fresh' END FreshnessStatus,agg.ServerId,agg.DatabaseId,agg.ServerName,agg.DatabaseName,0 ActiveCriticalCount,0 ActiveWarningCount,0 ActiveAttentionCount,0 RelatedSignalCount
 FROM agg;
END;
GO