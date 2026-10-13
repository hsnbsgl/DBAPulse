/*
   Historical snapshots remain available for audit, but deleted/inactive
   source objects must not appear in current operational screens.
*/

CREATE OR ALTER PROCEDURE dbo.usp_Capacity_Databases
    @Status nvarchar(30)=NULL,@ServerId int=NULL,@ForecastStatus nvarchar(30)=NULL,
    @PageNumber int=1,@PageSize int=50,@DatabaseId int=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
    SET @PageNumber=CASE WHEN @PageNumber<1 THEN 1 ELSE @PageNumber END;
    ;WITH x AS
    (
        SELECT c.DatabaseId,c.CollectedAtUtc,
               SUM(CASE WHEN c.FileType LIKE '%LOG%' THEN 0 ELSE c.AllocatedSizeMb END) DataMb,
               SUM(CASE WHEN c.FileType LIKE '%LOG%' THEN c.AllocatedSizeMb ELSE 0 END) LogMb
        FROM dbo.CapacitySnapshots c
        WHERE c.DatabaseId IS NOT NULL
        GROUP BY c.DatabaseId,c.CollectedAtUtc
    ), d AS
    (
        SELECT x.*,CAST(x.CollectedAtUtc AS date) DayValue,
               ROW_NUMBER() OVER(PARTITION BY x.DatabaseId,CAST(x.CollectedAtUtc AS date) ORDER BY x.CollectedAtUtc DESC) rn
        FROM x
    ), daily AS (SELECT * FROM d WHERE rn=1),
    current_row AS
    (
        SELECT *,ROW_NUMBER() OVER(PARTITION BY DatabaseId ORDER BY CollectedAtUtc DESC) current_rn
        FROM daily
    ), metrics AS
    (
        SELECT c.DatabaseId,c.DataMb,c.LogMb,c.DataMb+c.LogMb TotalMb,c.CollectedAtUtc,
               COUNT(s.DayValue) SampleCount,DATEDIFF(DAY,MIN(s.DayValue),MAX(s.DayValue)) HistoryDays
        FROM current_row c JOIN daily s ON s.DatabaseId=c.DatabaseId
        WHERE c.current_rn=1
        GROUP BY c.DatabaseId,c.DataMb,c.LogMb,c.CollectedAtUtc
    ), refs AS
    (
        SELECT m.*,r7.TotalMb Ref7,r30.TotalMb Ref30,r90.TotalMb Ref90
        FROM metrics m
        OUTER APPLY(SELECT TOP(1) DataMb+LogMb TotalMb FROM daily WHERE DatabaseId=m.DatabaseId AND DayValue<=DATEADD(DAY,-7,CAST(m.CollectedAtUtc AS date)) ORDER BY DayValue DESC) r7
        OUTER APPLY(SELECT TOP(1) DataMb+LogMb TotalMb FROM daily WHERE DatabaseId=m.DatabaseId AND DayValue<=DATEADD(DAY,-30,CAST(m.CollectedAtUtc AS date)) ORDER BY DayValue DESC) r30
        OUTER APPLY(SELECT TOP(1) DataMb+LogMb TotalMb FROM daily WHERE DatabaseId=m.DatabaseId AND DayValue<=DATEADD(DAY,-90,CAST(m.CollectedAtUtc AS date)) ORDER BY DayValue DESC) r90
    )
    SELECT db.Id DatabaseId,db.DatabaseName,s.ServerName,m.DataMb CurrentDataSizeMb,m.LogMb CurrentLogSizeMb,m.TotalMb CurrentTotalSizeMb,
           CASE WHEN Ref7 IS NULL THEN NULL ELSE m.TotalMb-Ref7 END Growth7dMb,
           CASE WHEN Ref30 IS NULL THEN NULL ELSE m.TotalMb-Ref30 END Growth30dMb,
           CASE WHEN Ref90 IS NULL THEN NULL ELSE m.TotalMb-Ref90 END Growth90dMb,
           CAST(NULL AS decimal(19,4)) GrowthRateMbPerDay,CAST(NULL AS decimal(19,2)) Forecast30dMb,
           CAST(NULL AS decimal(19,2)) Forecast90dMb,CAST(NULL AS decimal(19,6)) RSquared,
           m.SampleCount,m.HistoryDays,
           CASE WHEN m.SampleCount<7 OR m.HistoryDays<7 THEN 'InsufficientData' ELSE 'Usable' END ForecastStatus,
           CASE WHEN m.SampleCount<7 OR m.HistoryDays<7 THEN 'InsufficientData' ELSE 'Healthy' END CapacityStatus,
           m.CollectedAtUtc LastCollectedAtUtc,
           CASE WHEN m.CollectedAtUtc<DATEADD(HOUR,-3,SYSUTCDATETIME()) THEN 'Stale' ELSE 'Fresh' END DataFreshness
    FROM refs m
    JOIN dbo.Databases db ON db.Id=m.DatabaseId AND db.IsActive=1
    JOIN dbo.Servers s ON s.Id=db.ServerId AND s.IsActive=1
    WHERE (@DatabaseId IS NULL OR db.Id=@DatabaseId)
      AND (@ServerId IS NULL OR db.ServerId=@ServerId)
      AND (@ForecastStatus IS NULL OR @ForecastStatus=(CASE WHEN m.SampleCount<7 OR m.HistoryDays<7 THEN 'InsufficientData' ELSE 'Usable' END))
    ORDER BY db.DatabaseName
    OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    SELECT COUNT(*) TotalCount
    FROM dbo.Databases db JOIN dbo.Servers s ON s.Id=db.ServerId AND s.IsActive=1
    WHERE db.IsActive=1 AND (@DatabaseId IS NULL OR db.Id=@DatabaseId) AND (@ServerId IS NULL OR db.ServerId=@ServerId);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Capacity_Overview AS
BEGIN
    SET NOCOUNT ON;
    ;WITH x AS
    (
        SELECT c.DatabaseId,c.CollectedAtUtc,
               SUM(CASE WHEN c.FileType LIKE '%LOG%' THEN 0 ELSE c.AllocatedSizeMb END) DataMb,
               SUM(CASE WHEN c.FileType LIKE '%LOG%' THEN c.AllocatedSizeMb ELSE 0 END) LogMb
        FROM dbo.CapacitySnapshots c
        JOIN dbo.Databases d ON d.Id=c.DatabaseId AND d.IsActive=1
        JOIN dbo.Servers s ON s.Id=d.ServerId AND s.IsActive=1
        WHERE c.DatabaseId IS NOT NULL
        GROUP BY c.DatabaseId,c.CollectedAtUtc
    ), latest AS
    (
        SELECT *,ROW_NUMBER() OVER(PARTITION BY DatabaseId ORDER BY CollectedAtUtc DESC) rn FROM x
    ), previous AS
    (
        SELECT a.DatabaseId,a.DataMb+a.LogMb TotalMb,b.DataMb+b.LogMb PreviousMb
        FROM latest a
        OUTER APPLY(SELECT TOP(1) DataMb,LogMb FROM x z WHERE z.DatabaseId=a.DatabaseId AND z.CollectedAtUtc<=DATEADD(DAY,-30,a.CollectedAtUtc) ORDER BY z.CollectedAtUtc DESC)b
        WHERE a.rn=1
    )
    SELECT SUM(CASE WHEN rn=1 THEN DataMb+LogMb ELSE 0 END) TotalDatabaseSizeMb,
           SUM(CASE WHEN rn=1 AND PreviousMb IS NOT NULL THEN DataMb+LogMb-PreviousMb ELSE 0 END) Growth30dMb,
           0 DatabaseWarningCount,0 DatabaseCriticalCount,0 VolumeWarningCount,0 VolumeCriticalCount,
           0 ForecastableDatabaseCount,SUM(CASE WHEN rn=1 AND PreviousMb IS NULL THEN 1 ELSE 0 END) InsufficientDataCount,
           CAST(NULL AS decimal(19,2)) NearestExhaustionDays
    FROM (SELECT l.*,p.PreviousMb FROM latest l LEFT JOIN previous p ON p.DatabaseId=l.DatabaseId) q;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_Capacity AS
BEGIN
    SET NOCOUNT ON;
    ;WITH Latest AS
    (
        SELECT c.*,ROW_NUMBER() OVER(PARTITION BY c.DatabaseId,c.FileType ORDER BY c.CollectedAtUtc DESC,c.Id DESC) rn
        FROM dbo.CapacitySnapshots c
        JOIN dbo.Databases d ON d.Id=c.DatabaseId AND d.IsActive=1
        JOIN dbo.Servers s ON s.Id=c.ServerId AND s.IsActive=1
    ), CurrentRows AS (SELECT l.DatabaseId,l.DatabaseName,l.FileType,l.AllocatedSizeMb,l.CollectedAtUtc,l.ServerId FROM Latest l WHERE l.rn=1)
    SELECT COALESCE(SUM(CASE WHEN FileType=N'ROWS' THEN AllocatedSizeMb ELSE 0 END),0) TotalDataSizeMb,
           COALESCE(SUM(CASE WHEN FileType=N'LOG' THEN AllocatedSizeMb ELSE 0 END),0) TotalLogSizeMb,
           COALESCE(SUM(AllocatedSizeMb),0) TotalDatabaseSizeMb FROM CurrentRows;
    SELECT DatabaseId,DatabaseName,ServerId,
           SUM(CASE WHEN FileType=N'ROWS' THEN AllocatedSizeMb ELSE 0 END) DataSizeMb,
           SUM(CASE WHEN FileType=N'LOG' THEN AllocatedSizeMb ELSE 0 END) LogSizeMb,
           SUM(AllocatedSizeMb) TotalSizeMb,MAX(CollectedAtUtc) CollectedAtUtc
    FROM CurrentRows GROUP BY DatabaseId,DatabaseName,ServerId ORDER BY DatabaseName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_JobHealth_List
    @Status nvarchar(30)=NULL,@ServerId int=NULL,@Enabled bit=NULL,@RepeatedFailure bit=NULL,@Running bit=NULL,
    @PageNumber int=1,@PageSize int=50,@Id bigint=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
    SET @PageNumber=CASE WHEN @PageNumber<1 THEN 1 ELSE @PageNumber END;
    ;WITH LatestCollection AS
    (
        SELECT ServerId,MAX(CollectedAtUtc) CollectedAtUtc
        FROM dbo.JobSnapshots GROUP BY ServerId
    ), CurrentRows AS
    (
        SELECT j.Id,j.ServerId,s.ServerName,COALESCE(j.JobId,N'') JobId,j.JobName,j.Enabled,j.LastRunStatus,
               j.LastRunAtSource,j.LastRunDurationSeconds,j.IsRunning,j.CurrentStartAtSource,j.CurrentDurationSeconds,
               j.FailureCount24Hours,j.FailureCount7Days,j.RepeatedFailure,
               CAST(CASE WHEN j.IsRunning=1 AND j.CurrentDurationSeconds>1800 THEN 1 ELSE 0 END AS bit) IsLongRunning,
               j.CollectedAtUtc,
               CASE WHEN j.CollectedAtUtc<DATEADD(MINUTE,-30,SYSUTCDATETIME()) THEN N'Stale' ELSE N'Fresh' END DataFreshness,
               ROW_NUMBER() OVER(PARTITION BY j.ServerId,COALESCE(j.JobId,j.JobName) ORDER BY j.CollectedAtUtc DESC,j.Id DESC) rn
        FROM dbo.JobSnapshots j
        JOIN dbo.Servers s ON s.Id=j.ServerId AND s.IsActive=1
        JOIN LatestCollection lc ON lc.ServerId=j.ServerId AND lc.CollectedAtUtc=j.CollectedAtUtc
        WHERE @ServerId IS NULL OR j.ServerId=@ServerId
    )
    SELECT Id,ServerName,JobId,JobName,Enabled,LastRunStatus,LastRunAtSource,LastRunDurationSeconds,IsRunning,
           CurrentStartAtSource,CurrentDurationSeconds,FailureCount24Hours,FailureCount7Days,RepeatedFailure,
           IsLongRunning,CollectedAtUtc,DataFreshness
    INTO #Jobs FROM CurrentRows WHERE rn=1;
    SELECT * FROM #Jobs
    WHERE (@Id IS NULL OR Id=@Id) AND (@Status IS NULL OR LastRunStatus=@Status) AND (@Enabled IS NULL OR Enabled=@Enabled)
      AND (@RepeatedFailure IS NULL OR RepeatedFailure=@RepeatedFailure) AND (@Running IS NULL OR IsRunning=@Running)
    ORDER BY JobName OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    SELECT COUNT(*) TotalCount FROM #Jobs
    WHERE (@Id IS NULL OR Id=@Id) AND (@Status IS NULL OR LastRunStatus=@Status) AND (@Enabled IS NULL OR Enabled=@Enabled)
      AND (@RepeatedFailure IS NULL OR RepeatedFailure=@RepeatedFailure) AND (@Running IS NULL OR IsRunning=@Running);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AlwaysOnHealth_List
    @Health nvarchar(30)=NULL,@ServerId int=NULL,@Role nvarchar(60)=NULL,@SynchronizationState nvarchar(60)=NULL,
    @PageNumber int=1,@PageSize int=50,@Id bigint=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @PageSize=CASE WHEN @PageSize>100 THEN 100 WHEN @PageSize<1 THEN 1 ELSE @PageSize END;
    SET @PageNumber=CASE WHEN @PageNumber<1 THEN 1 ELSE @PageNumber END;
    ;WITH CurrentRows AS
    (
        SELECT a.Id,a.ServerId,s.ServerName,a.AvailabilityGroupName,a.ReplicaServerName,a.RoleDescription Role,
               a.OperationalState,a.ConnectedState,a.SynchronizationHealth,a.DatabaseName,a.SynchronizationState,
               a.DatabaseState,a.IsSuspended,a.SuspendReason,a.LogSendQueueMb,a.RedoQueueMb,
               CAST(NULL AS decimal(19,2)) EstimatedLagMinutes,a.CollectedAtUtc,
               CASE WHEN a.IsSuspended=1 OR a.ConnectedState=N'DISCONNECTED' OR a.SynchronizationHealth=N'NOT_HEALTHY' THEN N'Critical'
                    WHEN a.SynchronizationState=N'NOT SYNCHRONIZING' OR a.SynchronizationHealth=N'PARTIALLY_HEALTHY' THEN N'Warning' ELSE N'Healthy' END HealthStatus,
               CASE WHEN a.CollectedAtUtc<DATEADD(MINUTE,-30,SYSUTCDATETIME()) THEN N'Stale' ELSE N'Fresh' END DataFreshness,
               ROW_NUMBER() OVER(PARTITION BY a.ServerId,a.AvailabilityGroupName,a.ReplicaServerName,a.DatabaseName ORDER BY a.CollectedAtUtc DESC,a.Id DESC) rn
        FROM dbo.AlwaysOnSnapshots a
        JOIN dbo.Servers s ON s.Id=a.ServerId AND s.IsActive=1
        JOIN dbo.Databases d ON d.ServerId=a.ServerId AND d.DatabaseName=a.DatabaseName AND d.IsActive=1
        WHERE (@ServerId IS NULL OR a.ServerId=@ServerId)
    )
    SELECT Id,ServerName,AvailabilityGroupName,ReplicaServerName,Role,OperationalState,ConnectedState,SynchronizationHealth,
           DatabaseName,SynchronizationState,DatabaseState,IsSuspended,SuspendReason,LogSendQueueMb,RedoQueueMb,
           EstimatedLagMinutes,CollectedAtUtc,HealthStatus,DataFreshness
    INTO #AlwaysOn FROM CurrentRows WHERE rn=1;
    SELECT * FROM #AlwaysOn
    WHERE (@Id IS NULL OR Id=@Id) AND (@Role IS NULL OR Role=@Role) AND (@SynchronizationState IS NULL OR SynchronizationState=@SynchronizationState)
      AND (@Health IS NULL OR HealthStatus=@Health)
    ORDER BY CollectedAtUtc DESC OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    SELECT COUNT(*) TotalCount FROM #AlwaysOn
    WHERE (@Id IS NULL OR Id=@Id) AND (@Role IS NULL OR Role=@Role) AND (@SynchronizationState IS NULL OR SynchronizationState=@SynchronizationState)
      AND (@Health IS NULL OR HealthStatus=@Health);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Blocking_Recent @Hours int=24 AS
BEGIN
    SET NOCOUNT ON; SET @Hours=CASE WHEN @Hours IN(1,6,12,24,48,168) THEN @Hours ELSE 24 END;
    SELECT TOP(200) b.Id,b.CapturedAtUtc,s.ServerName,d.DatabaseName,b.SessionId,b.BlockingSessionId,b.WaitType,b.WaitDurationMs,
           b.Command,b.HostName,b.ApplicationName,b.LoginName,b.SqlTextHash,b.SqlTextPreview
    FROM dbo.BlockingEvents b JOIN dbo.Servers s ON s.Id=b.ServerId AND s.IsActive=1
    LEFT JOIN dbo.Databases d ON d.Id=b.DatabaseId AND d.IsActive=1
    WHERE b.CapturedAtUtc>=DATEADD(HOUR,-@Hours,SYSUTCDATETIME()) AND (b.DatabaseId IS NULL OR d.Id IS NOT NULL)
    ORDER BY b.CapturedAtUtc DESC,b.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Deadlocks_Recent @Hours int=24 AS
BEGIN
    SET NOCOUNT ON; SET @Hours=CASE WHEN @Hours IN(1,6,12,24,48,168) THEN @Hours ELSE 24 END;
    SELECT TOP(200) d.Id,d.OccurredAtUtc,d.CollectedAtUtc,s.ServerName,db.DatabaseName,d.VictimProcessId,d.VictimSessionId,d.ProcessCount,d.DeadlockHash
    FROM dbo.DeadlockEvents d JOIN dbo.Servers s ON s.Id=d.ServerId AND s.IsActive=1
    LEFT JOIN dbo.Databases db ON db.Id=d.DatabaseId AND db.IsActive=1
    WHERE d.OccurredAtUtc>=DATEADD(HOUR,-@Hours,SYSUTCDATETIME()) AND (d.DatabaseId IS NULL OR db.Id IS NOT NULL)
    ORDER BY d.OccurredAtUtc DESC,d.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LongRunning_Recent @Hours int=24 AS
BEGIN
    SET NOCOUNT ON; SET @Hours=CASE WHEN @Hours IN(1,6,12,24,48,168) THEN @Hours ELSE 24 END;
    SELECT TOP(200) r.Id,r.CapturedAtUtc,s.ServerName,d.DatabaseName,r.SessionId,r.ElapsedMs,r.Status,r.Command,r.WaitType,
           r.WaitTimeMs,r.CpuTimeMs,r.LogicalReads,r.Reads,r.Writes,r.HostName,r.ApplicationName,r.LoginName,r.SqlTextHash,r.SqlTextPreview
    FROM dbo.LongRunningRequestSnapshots r JOIN dbo.Servers s ON s.Id=r.ServerId AND s.IsActive=1
    LEFT JOIN dbo.Databases d ON d.Id=r.DatabaseId AND d.IsActive=1
    WHERE r.CapturedAtUtc>=DATEADD(HOUR,-@Hours,SYSUTCDATETIME()) AND (r.DatabaseId IS NULL OR d.Id IS NOT NULL)
    ORDER BY r.CapturedAtUtc DESC,r.ElapsedMs DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_OperationalEvents_List
    @FromUtc datetime2(3)=NULL,@ToUtc datetime2(3)=NULL,@Status nvarchar(20)=NULL,@Severity nvarchar(20)=NULL,
    @EventType nvarchar(40)=NULL,@ServerId int=NULL,@DatabaseId int=NULL,@Page int=1,@PageSize int=50
AS
BEGIN
    SET NOCOUNT ON; SET @Page=CASE WHEN @Page<1 THEN 1 ELSE @Page END; SET @PageSize=CASE WHEN @PageSize<1 THEN 50 WHEN @PageSize>100 THEN 100 ELSE @PageSize END;
    SELECT e.Id,e.EventType,s.ServerName,d.DatabaseName,e.Fingerprint,e.StartedAtUtc,e.LastSeenAtUtc,e.EndedAtUtc,e.DurationMs,e.Status,e.Severity,
           e.ObservationCount,e.AffectedSessionCount,e.Title,e.Summary
    FROM dbo.OperationalEvents e JOIN dbo.Servers s ON s.Id=e.ServerId AND s.IsActive=1
    LEFT JOIN dbo.Databases d ON d.Id=e.DatabaseId AND d.IsActive=1
    WHERE (e.DatabaseId IS NULL OR d.Id IS NOT NULL) AND (@FromUtc IS NULL OR e.StartedAtUtc>=@FromUtc) AND (@ToUtc IS NULL OR e.StartedAtUtc<=@ToUtc)
      AND (@Status IS NULL OR e.Status=@Status) AND (@Severity IS NULL OR e.Severity=@Severity) AND (@EventType IS NULL OR e.EventType=@EventType)
      AND (@ServerId IS NULL OR e.ServerId=@ServerId) AND (@DatabaseId IS NULL OR e.DatabaseId=@DatabaseId)
    ORDER BY CASE WHEN e.Status=N'Active' THEN 0 ELSE 1 END,e.LastSeenAtUtc DESC,e.Id DESC
    OFFSET (@Page-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    SELECT COUNT(*) TotalCount FROM dbo.OperationalEvents e LEFT JOIN dbo.Databases d ON d.Id=e.DatabaseId AND d.IsActive=1
    WHERE (e.DatabaseId IS NULL OR d.Id IS NOT NULL) AND (@FromUtc IS NULL OR e.StartedAtUtc>=@FromUtc) AND (@ToUtc IS NULL OR e.StartedAtUtc<=@ToUtc)
      AND (@Status IS NULL OR e.Status=@Status) AND (@Severity IS NULL OR e.Severity=@Severity) AND (@EventType IS NULL OR e.EventType=@EventType)
      AND (@ServerId IS NULL OR e.ServerId=@ServerId) AND (@DatabaseId IS NULL OR e.DatabaseId=@DatabaseId);
END;
GO
