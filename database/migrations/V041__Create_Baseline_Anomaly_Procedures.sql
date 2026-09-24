CREATE OR ALTER PROCEDURE dbo.usp_AnomalySamples_List
    @FromUtc datetime2(3),
    @ToUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT N'BlockingDuration', ServerId, DatabaseId, CAST(NULL AS nvarchar(256)), CapturedAtUtc, CONVERT(decimal(28,6), WaitDurationMs), Id
    FROM dbo.BlockingEvents WHERE CapturedAtUtc BETWEEN @FromUtc AND @ToUtc
    UNION ALL
    SELECT N'LongRunningDuration', ServerId, DatabaseId, SqlTextHash, CapturedAtUtc, CONVERT(decimal(28,6), ElapsedMs), Id
    FROM dbo.LongRunningRequestSnapshots WHERE CapturedAtUtc BETWEEN @FromUtc AND @ToUtc
    UNION ALL
    SELECT N'JobDuration', ServerId, NULL, JobId, CollectedAtUtc, CONVERT(decimal(28,6), LastRunDurationSeconds), Id
    FROM dbo.JobSnapshots WHERE CollectedAtUtc BETWEEN @FromUtc AND @ToUtc AND LastRunStatus = N'Succeeded' AND LastRunDurationSeconds IS NOT NULL
    UNION ALL
    SELECT N'BackupDuration', ServerId, DatabaseId, BackupType, CollectedAtUtc, CONVERT(decimal(28,6), BackupDurationSeconds), Id
    FROM dbo.BackupSnapshots WHERE CollectedAtUtc BETWEEN @FromUtc AND @ToUtc AND BackupDurationSeconds IS NOT NULL
    UNION ALL
    SELECT N'DatabaseGrowth', ServerId, DatabaseId, CAST(NULL AS nvarchar(256)), CollectedAtUtc, CONVERT(decimal(28,6), AllocatedSizeMb - LAG(AllocatedSizeMb) OVER (PARTITION BY ServerId, DatabaseId, FileType ORDER BY CollectedAtUtc)), Id
    FROM dbo.CapacitySnapshots WHERE CollectedAtUtc BETWEEN DATEADD(day, -1, @FromUtc) AND @ToUtc;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Baselines_Replace
    @Rows dbo.BaselineInputType READONLY,
    @CalculatedAtUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.Baselines WHERE CalculatedAtUtc < @CalculatedAtUtc;
    INSERT dbo.Baselines (MetricType,ServerId,DatabaseId,EntityKey,DayOfWeek,HourOfDay,WindowDays,SampleCount,MedianValue,P75Value,P90Value,P95Value,P99Value,MeanValue,StdDevValue,MadValue,MinValue,MaxValue,CalculatedAtUtc,ValidFromUtc,Status,BaselineScope)
    SELECT MetricType,ServerId,DatabaseId,EntityKey,DayOfWeek,HourOfDay,WindowDays,SampleCount,MedianValue,P75Value,P90Value,P95Value,P99Value,MeanValue,StdDevValue,MadValue,MinValue,MaxValue,CalculatedAtUtc,ValidFromUtc,Status,BaselineScope FROM @Rows;
    SELECT COUNT_BIG(*) FROM @Rows;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_AnomalyFindings_Upsert
    @Rows dbo.AnomalyFindingInputType READONLY,
    @AsOfUtc datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE target SET target.ObservedAtUtc = source.ObservedAtUtc, target.ObservedValue = source.ObservedValue, target.BaselineMedian = source.BaselineMedian, target.BaselineP95 = source.BaselineP95, target.BaselineP99 = source.BaselineP99, target.BaselineMad = source.BaselineMad, target.DeviationRatio = source.DeviationRatio, target.ModifiedZScore = source.ModifiedZScore, target.BaselineScope = source.BaselineScope, target.SampleCount = source.SampleCount, target.Severity = source.Severity, target.Status = source.Status, target.ExplanationCode = source.ExplanationCode, target.LastSeenAtUtc = source.ObservedAtUtc, target.EndedAtUtc = CASE WHEN source.Status = N'Resolved' THEN source.ObservedAtUtc ELSE NULL END, target.ObservationCount = target.ObservationCount + 1, target.UpdatedAtUtc = @AsOfUtc
    FROM dbo.AnomalyFindings target JOIN @Rows source ON source.Fingerprint = target.Fingerprint AND target.Status = N'Active';
    INSERT dbo.AnomalyFindings (MetricType,ServerId,DatabaseId,EntityKey,ObservedAtUtc,ObservedValue,BaselineMedian,BaselineP95,BaselineP99,BaselineMad,DeviationRatio,ModifiedZScore,BaselineScope,SampleCount,Severity,Status,ExplanationCode,Fingerprint,StartedAtUtc,LastSeenAtUtc,SourceEntityId)
    SELECT source.MetricType,source.ServerId,source.DatabaseId,source.EntityKey,source.ObservedAtUtc,source.ObservedValue,source.BaselineMedian,source.BaselineP95,source.BaselineP99,source.BaselineMad,source.DeviationRatio,source.ModifiedZScore,source.BaselineScope,source.SampleCount,source.Severity,source.Status,source.ExplanationCode,source.Fingerprint,source.ObservedAtUtc,source.ObservedAtUtc,source.SourceEntityId
    FROM @Rows source WHERE NOT EXISTS (SELECT 1 FROM dbo.AnomalyFindings target WHERE target.Fingerprint = source.Fingerprint AND target.Status = N'Active');
    SELECT @@ROWCOUNT;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Anomalies_ResolveStale
    @MetricType nvarchar(64), @AsOfUtc datetime2(3), @AfterSeconds int
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.AnomalyFindings SET Status = N'Resolved', EndedAtUtc = LastSeenAtUtc, UpdatedAtUtc = @AsOfUtc WHERE MetricType = @MetricType AND Status = N'Active' AND LastSeenAtUtc < DATEADD(second, -@AfterSeconds, @AsOfUtc);
    SELECT @@ROWCOUNT;
END;
GO
