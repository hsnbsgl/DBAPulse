CREATE OR ALTER PROCEDURE dbo.usp_ProtectionAvailability_Overview AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @now datetime2(3)=SYSUTCDATETIME(), @staleMinutes int=30;
 ;WITH latest AS (SELECT d.Id,d.RecoveryModel,d.DatabaseName,d.DatabaseStatus, ROW_NUMBER() OVER(PARTITION BY d.Id ORDER BY b.CollectedAtUtc DESC) rn, b.CollectedAtUtc, b.BackupType,b.BackupFinishAtSource FROM dbo.Databases d LEFT JOIN dbo.BackupSnapshots b ON b.DatabaseId=d.Id)
 SELECT
  SUM(CASE WHEN DatabaseStatus='ONLINE' AND RecoveryModel='SIMPLE' AND rn=1 AND BackupType='FULL' AND BackupFinishAtSource IS NOT NULL THEN 1 WHEN DatabaseStatus='ONLINE' AND RecoveryModel<>'SIMPLE' AND rn=1 AND BackupType='FULL' AND BackupFinishAtSource IS NOT NULL AND DATEDIFF(HOUR,BackupFinishAtSource,GETDATE())<=24 THEN 1 ELSE 0 END) ProtectedDatabaseCount,
  0 BackupWarningCount, 0 BackupCriticalCount, SUM(CASE WHEN rn=1 AND CollectedAtUtc < DATEADD(MINUTE,-@staleMinutes,@now) THEN 1 ELSE 0 END) BackupUnknownCount,
  (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.AlwaysOnSnapshots) AND a.SynchronizationHealth IN ('HEALTHY','PARTIALLY_HEALTHY')) AlwaysOnHealthyCount,
  (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.AlwaysOnSnapshots) AND a.SynchronizationHealth='NOT_HEALTHY') AlwaysOnWarningCount,
  0 AlwaysOnCriticalCount,
  (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.JobSnapshots) AND j.LastRunStatus='Failed') FailedJobCount,
  (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.JobSnapshots) AND j.IsRunning=1) RunningJobCount,
  (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.JobSnapshots) AND j.IsRunning=1 AND j.CurrentDurationSeconds>1800) LongRunningJobCount
 FROM latest;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_BackupProtection_List @Status nvarchar(30)=NULL,@ServerId int=NULL,@DatabaseId int=NULL,@RecoveryModel nvarchar(60)=NULL,@PageNumber int=1,@PageSize int=50 AS
BEGIN
 SET NOCOUNT ON; SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END; SET @PageNumber=CASE WHEN @PageNumber<1 THEN 1 ELSE @PageNumber END;
 ;WITH latest AS (SELECT b.*,ROW_NUMBER() OVER(PARTITION BY b.DatabaseId,b.BackupType ORDER BY b.CollectedAtUtc DESC,b.Id DESC) rn FROM dbo.BackupSnapshots b), agg AS
 (SELECT d.Id DatabaseId,d.DatabaseName,s.ServerName,d.ServerId,d.RecoveryModel,d.DatabaseStatus,MAX(CASE WHEN l.BackupType='FULL' AND l.rn=1 THEN l.BackupFinishAtSource END) LastFull,MAX(CASE WHEN l.BackupType='DIFFERENTIAL' AND l.rn=1 THEN l.BackupFinishAtSource END) LastDiff,MAX(CASE WHEN l.BackupType='LOG' AND l.rn=1 THEN l.BackupFinishAtSource END) LastLog,MAX(l.CollectedAtUtc) LastCollected FROM dbo.Databases d JOIN dbo.Servers s ON s.Id=d.ServerId LEFT JOIN latest l ON l.DatabaseId=d.Id GROUP BY d.Id,d.DatabaseName,s.ServerName,d.ServerId,d.RecoveryModel,d.DatabaseStatus)
 SELECT *,CASE WHEN DatabaseName='tempdb' THEN 'NotApplicable' WHEN LastCollected IS NULL THEN 'Unknown' WHEN LastFull IS NULL THEN 'NeverBackedUp' WHEN DATEDIFF(HOUR,LastFull,GETDATE())>24 THEN 'Critical' WHEN DATEDIFF(HOUR,LastFull,GETDATE())>=19 THEN 'Warning' ELSE 'Protected' END ProtectionStatus, DATEDIFF(MINUTE,LastFull,GETDATE()) BackupAgeMinutes,DATEDIFF(MINUTE,LastLog,GETDATE()) LogBackupAgeMinutes,CASE WHEN LastCollected < DATEADD(MINUTE,-30,SYSUTCDATETIME()) THEN 'Stale' ELSE 'Fresh' END DataFreshness FROM agg WHERE (@ServerId IS NULL OR ServerId=@ServerId) AND (@DatabaseId IS NULL OR DatabaseId=@DatabaseId) AND (@RecoveryModel IS NULL OR RecoveryModel=@RecoveryModel) AND (@Status IS NULL OR @Status=(CASE WHEN DatabaseName='tempdb' THEN 'NotApplicable' WHEN LastFull IS NULL THEN 'NeverBackedUp' WHEN DATEDIFF(HOUR,LastFull,GETDATE())>24 THEN 'Critical' WHEN DATEDIFF(HOUR,LastFull,GETDATE())>=19 THEN 'Warning' ELSE 'Protected' END)) ORDER BY DatabaseName OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
 SELECT COUNT(*) TotalCount FROM dbo.Databases;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_AlwaysOnHealth_List @Health nvarchar(30)=NULL,@ServerId int=NULL,@Role nvarchar(60)=NULL,@SynchronizationState nvarchar(60)=NULL,@PageNumber int=1,@PageSize int=50 AS
BEGIN
 SET NOCOUNT ON; SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
 SELECT a.Id,s.ServerName,a.AvailabilityGroupName,a.ReplicaServerName,a.RoleDescription Role,a.OperationalState,a.ConnectedState,a.SynchronizationHealth,a.DatabaseName,a.SynchronizationState,a.DatabaseState,a.IsSuspended,a.SuspendReason,a.LogSendQueueMb,a.RedoQueueMb,CAST(NULL AS decimal(19,2)) EstimatedLagMinutes,a.CollectedAtUtc,CASE WHEN a.IsSuspended=1 OR a.ConnectedState='DISCONNECTED' OR a.SynchronizationHealth='NOT_HEALTHY' THEN 'Critical' WHEN a.SynchronizationState='NOT SYNCHRONIZING' OR a.SynchronizationHealth='PARTIALLY_HEALTHY' THEN 'Warning' ELSE 'Healthy' END HealthStatus,CASE WHEN a.CollectedAtUtc<DATEADD(MINUTE,-30,SYSUTCDATETIME()) THEN 'Stale' ELSE 'Fresh' END DataFreshness FROM dbo.AlwaysOnSnapshots a JOIN dbo.Servers s ON s.Id=a.ServerId WHERE a.CollectedAtUtc=(SELECT MAX(x.CollectedAtUtc) FROM dbo.AlwaysOnSnapshots x WHERE x.ServerId=a.ServerId) AND (@ServerId IS NULL OR a.ServerId=@ServerId) AND (@Role IS NULL OR a.RoleDescription=@Role) AND (@SynchronizationState IS NULL OR a.SynchronizationState=@SynchronizationState) AND (@Health IS NULL OR @Health=(CASE WHEN a.IsSuspended=1 OR a.ConnectedState='DISCONNECTED' OR a.SynchronizationHealth='NOT_HEALTHY' THEN 'Critical' WHEN a.SynchronizationState='NOT SYNCHRONIZING' OR a.SynchronizationHealth='PARTIALLY_HEALTHY' THEN 'Warning' ELSE 'Healthy' END)) ORDER BY a.CollectedAtUtc DESC OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
 SELECT COUNT(*) TotalCount FROM dbo.AlwaysOnSnapshots WHERE CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.AlwaysOnSnapshots);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_JobHealth_List @Status nvarchar(30)=NULL,@ServerId int=NULL,@Enabled bit=NULL,@RepeatedFailure bit=NULL,@Running bit=NULL,@PageNumber int=1,@PageSize int=50 AS
BEGIN
 SET NOCOUNT ON; SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
 ;WITH x AS (SELECT j.*,s.ServerName,ROW_NUMBER() OVER(PARTITION BY j.ServerId,COALESCE(j.JobId,j.JobName) ORDER BY j.CollectedAtUtc DESC,j.Id DESC) rn FROM dbo.JobSnapshots j JOIN dbo.Servers s ON s.Id=j.ServerId)
 SELECT Id,ServerName,COALESCE(JobId,N'') JobId,JobName,Enabled,LastRunStatus,LastRunAtSource,LastRunDurationSeconds,IsRunning,CurrentStartAtSource,CurrentDurationSeconds,FailureCount24Hours,FailureCount7Days,RepeatedFailure,CAST(CASE WHEN IsRunning=1 AND CurrentDurationSeconds>1800 THEN 1 ELSE 0 END AS bit) IsLongRunning,CollectedAtUtc,CASE WHEN CollectedAtUtc<DATEADD(MINUTE,-30,SYSUTCDATETIME()) THEN 'Stale' ELSE 'Fresh' END DataFreshness FROM x WHERE rn=1 AND (@Status IS NULL OR LastRunStatus=@Status) AND (@ServerId IS NULL OR ServerId=@ServerId) AND (@Enabled IS NULL OR Enabled=@Enabled) AND (@RepeatedFailure IS NULL OR RepeatedFailure=@RepeatedFailure) AND (@Running IS NULL OR IsRunning=@Running) ORDER BY JobName OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
 SELECT COUNT(*) TotalCount FROM (SELECT ROW_NUMBER() OVER(PARTITION BY ServerId,COALESCE(JobId,JobName) ORDER BY CollectedAtUtc DESC,Id DESC) rn FROM dbo.JobSnapshots) q WHERE rn=1;
END;
