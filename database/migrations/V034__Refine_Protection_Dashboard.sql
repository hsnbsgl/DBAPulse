CREATE OR ALTER PROCEDURE dbo.usp_ProtectionAvailability_Overview AS
BEGIN
 SET NOCOUNT ON;
 ;WITH p AS
 (
  SELECT d.Id,d.DatabaseName,d.RecoveryModel,d.DatabaseStatus,
   f.LastFull,l.LastLog
  FROM dbo.Databases d
  OUTER APPLY (SELECT TOP(1) BackupFinishAtSource LastFull FROM dbo.BackupSnapshots b WHERE b.DatabaseId=d.Id AND b.BackupType='FULL' ORDER BY b.CollectedAtUtc DESC,b.Id DESC) f
  OUTER APPLY (SELECT TOP(1) BackupFinishAtSource LastLog FROM dbo.BackupSnapshots b WHERE b.DatabaseId=d.Id AND b.BackupType='LOG' ORDER BY b.CollectedAtUtc DESC,b.Id DESC) l
 )
 SELECT
  SUM(CASE WHEN DatabaseName='tempdb' THEN 0 WHEN LastFull IS NOT NULL AND DATEDIFF(HOUR,LastFull,GETDATE())<=24 AND (RecoveryModel='SIMPLE' OR (LastLog IS NOT NULL AND DATEDIFF(MINUTE,LastLog,GETDATE())<=60)) THEN 1 ELSE 0 END) ProtectedDatabaseCount,
  SUM(CASE WHEN DatabaseName<>'tempdb' AND LastFull IS NOT NULL AND ((DATEDIFF(HOUR,LastFull,GETDATE()) BETWEEN 19 AND 24) OR (RecoveryModel<>'SIMPLE' AND LastLog IS NOT NULL AND DATEDIFF(MINUTE,LastLog,GETDATE()) BETWEEN 45 AND 60)) THEN 1 ELSE 0 END) BackupWarningCount,
  SUM(CASE WHEN DatabaseName<>'tempdb' AND (LastFull IS NULL OR DATEDIFF(HOUR,LastFull,GETDATE())>24 OR (RecoveryModel<>'SIMPLE' AND (LastLog IS NULL OR DATEDIFF(MINUTE,LastLog,GETDATE())>60))) THEN 1 ELSE 0 END) BackupCriticalCount,
  0 BackupUnknownCount,
  (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.AlwaysOnSnapshots) AND a.SynchronizationHealth IN ('HEALTHY','PARTIALLY_HEALTHY')) AlwaysOnHealthyCount,
  (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.AlwaysOnSnapshots) AND a.SynchronizationHealth='PARTIALLY_HEALTHY') AlwaysOnWarningCount,
  (SELECT COUNT(*) FROM dbo.AlwaysOnSnapshots a WHERE a.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.AlwaysOnSnapshots) AND (a.IsSuspended=1 OR a.ConnectedState='DISCONNECTED' OR a.SynchronizationHealth='NOT_HEALTHY')) AlwaysOnCriticalCount,
  (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.JobSnapshots) AND j.LastRunStatus='Failed') FailedJobCount,
  (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.JobSnapshots) AND j.IsRunning=1) RunningJobCount,
  (SELECT COUNT(*) FROM dbo.JobSnapshots j WHERE j.CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.JobSnapshots) AND j.IsRunning=1 AND j.CurrentDurationSeconds>1800) LongRunningJobCount
 FROM p;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_AlwaysOnHealth_List @Health nvarchar(30)=NULL,@ServerId int=NULL,@Role nvarchar(60)=NULL,@SynchronizationState nvarchar(60)=NULL,@PageNumber int=1,@PageSize int=50,@Id bigint=NULL AS
BEGIN
 SET NOCOUNT ON; SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
 SELECT a.Id,s.ServerName,a.AvailabilityGroupName,a.ReplicaServerName,a.RoleDescription Role,a.OperationalState,a.ConnectedState,a.SynchronizationHealth,a.DatabaseName,a.SynchronizationState,a.DatabaseState,a.IsSuspended,a.SuspendReason,a.LogSendQueueMb,a.RedoQueueMb,CAST(NULL AS decimal(19,2)) EstimatedLagMinutes,a.CollectedAtUtc,CASE WHEN a.IsSuspended=1 OR a.ConnectedState='DISCONNECTED' OR a.SynchronizationHealth='NOT_HEALTHY' THEN 'Critical' WHEN a.SynchronizationState='NOT SYNCHRONIZING' OR a.SynchronizationHealth='PARTIALLY_HEALTHY' THEN 'Warning' ELSE 'Healthy' END HealthStatus,CASE WHEN a.CollectedAtUtc<DATEADD(MINUTE,-30,SYSUTCDATETIME()) THEN 'Stale' ELSE 'Fresh' END DataFreshness FROM dbo.AlwaysOnSnapshots a JOIN dbo.Servers s ON s.Id=a.ServerId WHERE a.CollectedAtUtc=(SELECT MAX(x.CollectedAtUtc) FROM dbo.AlwaysOnSnapshots x WHERE x.ServerId=a.ServerId) AND (@Id IS NULL OR a.Id=@Id) AND (@ServerId IS NULL OR a.ServerId=@ServerId) AND (@Role IS NULL OR a.RoleDescription=@Role) AND (@SynchronizationState IS NULL OR a.SynchronizationState=@SynchronizationState) AND (@Health IS NULL OR @Health=(CASE WHEN a.IsSuspended=1 OR a.ConnectedState='DISCONNECTED' OR a.SynchronizationHealth='NOT_HEALTHY' THEN 'Critical' WHEN a.SynchronizationState='NOT SYNCHRONIZING' OR a.SynchronizationHealth='PARTIALLY_HEALTHY' THEN 'Warning' ELSE 'Healthy' END)) ORDER BY a.CollectedAtUtc DESC OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
 SELECT COUNT(*) TotalCount FROM dbo.AlwaysOnSnapshots WHERE CollectedAtUtc=(SELECT MAX(CollectedAtUtc) FROM dbo.AlwaysOnSnapshots) AND (@Id IS NULL OR Id=@Id);
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_JobHealth_List @Status nvarchar(30)=NULL,@ServerId int=NULL,@Enabled bit=NULL,@RepeatedFailure bit=NULL,@Running bit=NULL,@PageNumber int=1,@PageSize int=50,@Id bigint=NULL AS
BEGIN
 SET NOCOUNT ON; SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
 ;WITH x AS (SELECT j.*,s.ServerName,ROW_NUMBER() OVER(PARTITION BY j.ServerId,COALESCE(j.JobId,j.JobName) ORDER BY j.CollectedAtUtc DESC,j.Id DESC) rn FROM dbo.JobSnapshots j JOIN dbo.Servers s ON s.Id=j.ServerId)
 SELECT Id,ServerName,COALESCE(JobId,N'') JobId,JobName,Enabled,LastRunStatus,LastRunAtSource,LastRunDurationSeconds,IsRunning,CurrentStartAtSource,CurrentDurationSeconds,FailureCount24Hours,FailureCount7Days,RepeatedFailure,CAST(CASE WHEN IsRunning=1 AND CurrentDurationSeconds>1800 THEN 1 ELSE 0 END AS bit) IsLongRunning,CollectedAtUtc,CASE WHEN CollectedAtUtc<DATEADD(MINUTE,-30,SYSUTCDATETIME()) THEN 'Stale' ELSE 'Fresh' END DataFreshness FROM x WHERE rn=1 AND (@Id IS NULL OR Id=@Id) AND (@Status IS NULL OR LastRunStatus=@Status) AND (@ServerId IS NULL OR ServerId=@ServerId) AND (@Enabled IS NULL OR Enabled=@Enabled) AND (@RepeatedFailure IS NULL OR RepeatedFailure=@RepeatedFailure) AND (@Running IS NULL OR IsRunning=@Running) ORDER BY JobName OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
 SELECT COUNT(*) TotalCount FROM (SELECT Id,ROW_NUMBER() OVER(PARTITION BY ServerId,COALESCE(JobId,JobName) ORDER BY CollectedAtUtc DESC,Id DESC) rn FROM dbo.JobSnapshots) q WHERE rn=1 AND (@Id IS NULL OR Id=@Id);
END;
