using System.Data;
using System.Diagnostics;
using DBAPulse.Data;
using DBAPulse.Domain;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace DBAPulse.Collector;

public sealed class CollectorWorker : BackgroundService
{
    private readonly SourceQueryClient _source;
    private readonly ManagementStore _store;
    private readonly ILogger<CollectorWorker> _logger;
    private readonly string _timeZone;
    private readonly TimeSpan _interval;
    private TimeSpan _capacityInterval;
    private DateTime _lastCapacityCollectedAtUtc = DateTime.MinValue;
    private readonly Dictionary<int, DateTime> _lastServerCollectedAtUtc = new();
    private readonly bool _runOnce;
    private readonly long _longRunningThresholdMs;
    private readonly IHostApplicationLifetime _lifetime;
    private readonly OperationalEventCorrelator _correlator;
    private readonly int _blockingResolveSeconds, _longRunningResolveSeconds, _protectionResolveSeconds;
    private readonly AnomalyEngine _anomalyEngine;
    private readonly int _anomalyResolveSeconds;

    public CollectorWorker(SourceQueryClient source, ManagementStore store, IConfiguration configuration, ILogger<CollectorWorker> logger, IHostApplicationLifetime lifetime, OperationalEventCorrelator correlator, AnomalyEngine anomalyEngine)
    {
        _source = source; _store = store; _logger = logger;
        _timeZone = configuration["DBAPULSE_DISPLAY_TIMEZONE"] ?? "Europe/Istanbul";
        _interval = TimeSpan.FromMinutes(1);
        _capacityInterval = TimeSpan.FromMinutes(Math.Max(1, int.TryParse(configuration["DBAPULSE_CAPACITY_INTERVAL_MINUTES"], out var capacityMinutes) ? capacityMinutes : 60));
        _runOnce = string.Equals(configuration["DBAPULSE_RUN_ONCE"], "true", StringComparison.OrdinalIgnoreCase);
        var longRunningSeconds = int.TryParse(configuration["DBAPULSE_LONG_RUNNING_SECONDS"], out var configuredSeconds) ? configuredSeconds : 60;
        _longRunningThresholdMs = Math.Max(1, longRunningSeconds) * 1000L;
        _lifetime = lifetime;
        _correlator = correlator; _anomalyEngine = anomalyEngine;
        _blockingResolveSeconds = int.TryParse(configuration["DBAPULSE_BLOCKING_RESOLVE_AFTER_SECONDS"], out var blockingResolve) ? Math.Max(1, blockingResolve) : 180;
        _longRunningResolveSeconds = int.TryParse(configuration["DBAPULSE_LONGRUNNING_RESOLVE_AFTER_SECONDS"], out var longResolve) ? Math.Max(1, longResolve) : 180;
        _protectionResolveSeconds = int.TryParse(configuration["DBAPULSE_PROTECTION_RESOLVE_AFTER_SECONDS"], out var protectionResolve) ? Math.Max(1, protectionResolve) : 900;
        _anomalyResolveSeconds = int.TryParse(configuration["DBAPULSE_ANOMALY_RESOLVE_AFTER_SECONDS"], out var anomalyResolve) ? Math.Max(1, anomalyResolve) : 900;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("DBA Pulse Collector starting; display timezone {TimeZone}", _timeZone);
        do
        {
            await CollectAsync(stoppingToken);
            if (_runOnce) { _lifetime.StopApplication(); break; }
            await Task.Delay(_interval, stoppingToken);
        } while (!_runOnce && !stoppingToken.IsCancellationRequested);
    }

    private async Task CollectAsync(CancellationToken token)
    {
        var started = DateTime.UtcNow; var stopwatch = Stopwatch.StartNew(); long runId = 0; var errors = 0;
        try
        {
            runId = await _store.StartRunAsync(started, token);
            _logger.LogInformation("Collection #{RunId} started", runId);
            var servers = await _source.ReadServersAsync(token);
            LogRows("inventory/server-info.sql", servers.Count);
            if (servers.Count == 0) throw new InvalidOperationException("Server inventory returned zero rows");
            var serverInputs = servers.Select(s => new ServerInput(s.ServerName, s.InstanceName, s.SqlVersion, s.Edition, _timeZone, DateTimeOffset.UtcNow, true)).ToArray();
            var serverIds = await _store.SyncServersAsync(serverInputs, token);
            _logger.LogInformation("Servers sync OK - {Count} rows", serverIds.Count);
            var activeServers = new List<ServerInventory>();
            foreach (var server in servers)
            {
                if (serverIds.TryGetValue(server.ServerName, out var id) && await _store.IsServerActiveAsync(id, token)) activeServers.Add(server);
                else _logger.LogInformation("Skipping inactive server {ServerName}", server.ServerName);
            }
            if (activeServers.Count == 0)
            {
                stopwatch.Stop();
                await _store.CompleteRunAsync(runId, "Skipped", DateTime.UtcNow, stopwatch.ElapsedMilliseconds, token);
                _logger.LogInformation("Collection #{RunId} skipped because all discovered servers are inactive", runId);
                return;
            }
            servers = activeServers;
            var primaryServerId = serverIds[servers[0].ServerName];
            var serverIntervals = await _store.GetServerIntervalsAsync(primaryServerId, token);
            var nowUtc = DateTime.UtcNow;
            if (_lastServerCollectedAtUtc.TryGetValue(primaryServerId, out var lastCollectedAtUtc) && nowUtc - lastCollectedAtUtc < TimeSpan.FromMinutes(serverIntervals.CollectionIntervalMinutes))
            {
                stopwatch.Stop();
                await _store.CompleteRunAsync(runId, "Skipped", nowUtc, stopwatch.ElapsedMilliseconds, token);
                _logger.LogInformation("Collection #{RunId} skipped for server {ServerId}; interval is {IntervalMinutes} minutes", runId, primaryServerId, serverIntervals.CollectionIntervalMinutes);
                return;
            }
            _lastServerCollectedAtUtc[primaryServerId] = nowUtc;
            _capacityInterval = TimeSpan.FromMinutes(serverIntervals.CapacityIntervalMinutes);

            var serverSnapshot = Table(("CollectionRunId", typeof(long)), ("ServerId", typeof(int)), ("CollectedAtUtc", typeof(DateTime)), ("UptimeSeconds", typeof(long)));
            foreach (var server in servers.Where(s => serverIds.ContainsKey(s.ServerName))) serverSnapshot.Rows.Add(runId, serverIds[server.ServerName], DateTime.UtcNow, Db(server.UptimeSeconds));
            _logger.LogInformation("ServerSnapshots {Count} rows inserted", await _store.InsertServerSnapshotsAsync(serverSnapshot, token));

            var databases = await _source.ReadDatabasesAsync(token);
            LogRows("inventory/databases.sql", databases.Count);
            var serverId = serverIds[servers[0].ServerName];
            var databaseInputs = databases.Select(d => new DatabaseInput(serverId, d.DatabaseName, d.RecoveryModel, d.DatabaseStatus, DateTimeOffset.UtcNow, true)).ToArray();
            var databaseIds = await _store.SyncDatabasesAsync(databaseInputs, token);
            _logger.LogInformation("Databases sync OK - {Count} rows", databaseIds.Count);

            var databaseSnapshot = Table(("CollectionRunId", typeof(long)), ("DatabaseId", typeof(int)), ("CollectedAtUtc", typeof(DateTime)), ("DatabaseStatus", typeof(string)), ("UserAccess", typeof(string)), ("CompatibilityLevel", typeof(int)), ("IsReadOnly", typeof(bool)), ("IsEncrypted", typeof(bool)));
            foreach (var database in databases.Where(d => databaseIds.ContainsKey(d.DatabaseName))) databaseSnapshot.Rows.Add(runId, databaseIds[database.DatabaseName], DateTime.UtcNow, database.DatabaseStatus, database.UserAccess, database.CompatibilityLevel, database.IsReadOnly, database.IsEncrypted);
            _logger.LogInformation("DatabaseSnapshots {Count} rows inserted", await _store.InsertDatabaseSnapshotsAsync(databaseSnapshot, token));

            errors += await RunDomainAsync(runId, "backup/last-backups.sql", async () =>
            {
                var rows = await _source.ReadBackupsAsync(token); LogRows("backup/last-backups.sql", rows.Count);
                var table = Table(("CollectionRunId", typeof(long)), ("ServerId", typeof(int)), ("DatabaseId", typeof(int)), ("DatabaseName", typeof(string)), ("CollectedAtUtc", typeof(DateTime)), ("BackupType", typeof(string)), ("BackupStartAtSource", typeof(DateTime)), ("BackupFinishAtSource", typeof(DateTime)), ("BackupSizeMb", typeof(decimal)), ("CompressedBackupSizeMb", typeof(decimal)), ("IsCopyOnly", typeof(bool)), ("BackupDurationSeconds", typeof(int)));
                foreach (var r in rows) table.Rows.Add(runId, serverId, Db(databaseIds, r.DatabaseName), r.DatabaseName, DateTime.UtcNow, r.BackupType, Db(r.BackupStart), Db(r.BackupFinish), Db(r.BackupSizeMb), Db(r.CompressedBackupSizeMb), r.IsCopyOnly, Db(r.DurationSeconds));
                _logger.LogInformation("BackupSnapshots {Count} rows inserted", await _store.InsertProtectionBackupsAsync(table, token));
                var events = _correlator.BackupProtection(databases, rows, serverId, databaseIds, DateTime.UtcNow);
                _logger.LogInformation("Backup protection operational events correlated: {Count}", await _store.UpsertOperationalEventsAsync(events, DateTime.UtcNow, token));
                await _store.ResolveOperationalEventsAsync("BackupProtection", _protectionResolveSeconds, DateTime.UtcNow, token);
            }, token);
            errors += await RunDomainAsync(runId, "jobs/job-status.sql", async () =>
            {
                var rows = await _source.ReadJobsAsync(token); LogRows("jobs/job-status.sql", rows.Count);
                var table = Table(("CollectionRunId", typeof(long)), ("ServerId", typeof(int)), ("CollectedAtUtc", typeof(DateTime)), ("JobId", typeof(string)), ("JobName", typeof(string)), ("Enabled", typeof(bool)), ("LastRunStatus", typeof(string)), ("LastRunAtSource", typeof(DateTime)), ("LastRunDurationSeconds", typeof(int)), ("LastRunMessage", typeof(string)), ("IsRunning", typeof(bool)), ("CurrentStartAtSource", typeof(DateTime)), ("CurrentDurationSeconds", typeof(int)), ("NextRunAtSource", typeof(DateTime)), ("FailureCount24Hours", typeof(int)), ("FailureCount7Days", typeof(int)), ("RepeatedFailure", typeof(bool)), ("AverageDurationSeconds", typeof(int)), ("MaxDurationSeconds", typeof(int)));
                foreach (var r in rows) table.Rows.Add(runId, serverId, DateTime.UtcNow, r.JobId, r.JobName, r.Enabled, r.LastRunStatus, Db(r.LastRunAtSource), Db(r.LastRunDurationSeconds), Db(r.LastRunMessage), r.IsRunning, Db(r.CurrentStartAtSource), Db(r.CurrentDurationSeconds), Db(r.NextRunAtSource), r.FailureCount24Hours, r.FailureCount7Days, r.RepeatedFailure, Db(r.AverageDurationSeconds), Db(r.MaxDurationSeconds));
                _logger.LogInformation("JobSnapshots {Count} rows inserted", await _store.InsertProtectionJobsAsync(table, token));
                var events = _correlator.JobFailures(rows, serverId, DateTime.UtcNow);
                _logger.LogInformation("Job failure operational events correlated: {Count}", await _store.UpsertOperationalEventsAsync(events, DateTime.UtcNow, token));
                await _store.ResolveOperationalEventsAsync("JobFailure", _protectionResolveSeconds, DateTime.UtcNow, token);
            }, token);
            errors += await RunDomainAsync(runId, "alwayson/ag-health.sql", async () =>
            {
                var rows = await _source.ReadAlwaysOnAsync(token); LogRows("alwayson/ag-health.sql", rows.Count);
                var table = Table(("CollectionRunId", typeof(long)), ("ServerId", typeof(int)), ("CollectedAtUtc", typeof(DateTime)), ("AvailabilityGroupName", typeof(string)), ("ReplicaServerName", typeof(string)), ("RoleDescription", typeof(string)), ("OperationalState", typeof(string)), ("ConnectedState", typeof(string)), ("SynchronizationHealth", typeof(string)), ("DatabaseName", typeof(string)), ("SynchronizationState", typeof(string)), ("DatabaseState", typeof(string)), ("IsSuspended", typeof(bool)), ("SuspendReason", typeof(string)), ("LogSendQueueMb", typeof(decimal)), ("RedoQueueMb", typeof(decimal)), ("LogSendRateMb", typeof(decimal)), ("RedoRateMb", typeof(decimal)), ("LastCommitTimeSource", typeof(DateTime)));
                foreach (var r in rows) table.Rows.Add(runId, serverId, DateTime.UtcNow, Db(r.AvailabilityGroupName), Db(r.ReplicaServerName), Db(r.Role), Db(r.OperationalState), Db(r.ConnectedState), Db(r.SynchronizationHealth), Db(r.DatabaseName), Db(r.SynchronizationState), Db(r.DatabaseState), r.IsSuspended, Db(r.SuspendReason), Db(r.LogSendQueueMb), Db(r.RedoQueueMb), Db(r.LogSendRateMb), Db(r.RedoRateMb), Db(r.LastCommitTimeSource));
                _logger.LogInformation("AlwaysOnSnapshots {Count} rows inserted", await _store.InsertProtectionAlwaysOnAsync(table, token));
                var events = _correlator.AlwaysOnHealth(rows, serverId, DateTime.UtcNow);
                _logger.LogInformation("Always On operational events correlated: {Count}", await _store.UpsertOperationalEventsAsync(events, DateTime.UtcNow, token));
                await _store.ResolveOperationalEventsAsync("AlwaysOnHealth", _protectionResolveSeconds, DateTime.UtcNow, token);
            }, token);
            errors += await RunDomainAsync(runId, "capacity/database-size.sql", async () =>
            {
                if (DateTime.UtcNow - _lastCapacityCollectedAtUtc < _capacityInterval) { _logger.LogInformation("Capacity collection skipped; next interval in {IntervalMinutes} minutes", _capacityInterval.TotalMinutes); return; }
                var rows = await _source.ReadCapacityAsync(token); LogRows("capacity/database-size.sql", rows.Count);
                var table = Table(("CollectionRunId", typeof(long)), ("ServerId", typeof(int)), ("DatabaseId", typeof(int)), ("DatabaseName", typeof(string)), ("CollectedAtUtc", typeof(DateTime)), ("FileType", typeof(string)), ("AllocatedSizeMb", typeof(decimal)), ("FileCount", typeof(int)));
                foreach (var r in rows) table.Rows.Add(runId, serverId, Db(databaseIds, r.DatabaseName), r.DatabaseName, DateTime.UtcNow, r.FileType, r.AllocatedSizeMb, r.FileCount);
                _logger.LogInformation("CapacitySnapshots {Count} rows inserted", await _store.InsertCapacitySnapshotsAsync(table, token));
                var volumes = await _source.ReadVolumesAsync(token); LogRows("capacity/volumes.sql", volumes.Count);
                var volumeTable = Table(("CollectionRunId", typeof(long)), ("ServerId", typeof(int)), ("VolumeId", typeof(string)), ("CollectedAtUtc", typeof(DateTime)), ("TotalBytes", typeof(long)), ("AvailableBytes", typeof(long)));
                foreach (var v in volumes) volumeTable.Rows.Add(runId, serverId, v.VolumeId, DateTime.UtcNow, v.TotalBytes, v.AvailableBytes);
                _logger.LogInformation("VolumeCapacitySnapshots {Count} rows inserted", await _store.InsertVolumeCapacitySnapshotsAsync(volumeTable, token));
                _lastCapacityCollectedAtUtc = DateTime.UtcNow;
            }, token);
            var performanceCapturedAtUtc = DateTime.UtcNow;
            errors += await RunDomainAsync(runId, "performance/blocking.sql", async () =>
            {
                var rows = await _source.ReadBlockingAsync(token); LogRows("performance/blocking.sql", rows.Count);
                _logger.LogInformation("BlockingEvents {Count} rows inserted", await _store.InsertBlockingAsync(rows, runId, serverId, databaseIds, performanceCapturedAtUtc, token));
                var events = _correlator.Blocking(rows, serverId, databaseIds, performanceCapturedAtUtc);
                _logger.LogInformation("Blocking operational events correlated: {Count}", await _store.UpsertOperationalEventsAsync(events, performanceCapturedAtUtc, token));
                await _store.ResolveOperationalEventsAsync("Blocking", _blockingResolveSeconds, performanceCapturedAtUtc, token);
            }, token);
            errors += await RunDomainAsync(runId, "performance/long-running-requests.sql", async () =>
            {
                var rows = await _source.ReadLongRunningAsync(_longRunningThresholdMs, token); LogRows("performance/long-running-requests.sql", rows.Count);
                _logger.LogInformation("LongRunningRequestSnapshots {Count} rows inserted", await _store.InsertLongRunningAsync(rows, serverId, databaseIds, performanceCapturedAtUtc, token));
                var events = _correlator.LongRunning(rows, serverId, databaseIds, performanceCapturedAtUtc);
                _logger.LogInformation("Long-running operational events correlated: {Count}", await _store.UpsertOperationalEventsAsync(events, performanceCapturedAtUtc, token));
                await _store.ResolveOperationalEventsAsync("LongRunning", _longRunningResolveSeconds, performanceCapturedAtUtc, token);
            }, token);
            errors += await RunDomainAsync(runId, "performance/wait-stats.sql", async () =>
            {
                var rows = await _source.ReadWaitStatsAsync(token); LogRows("performance/wait-stats.sql", rows.Count);
                _logger.LogInformation("WaitStatsSnapshots {Count} rows inserted", await _store.InsertWaitStatsAsync(rows, serverId, performanceCapturedAtUtc, token));
            }, token);
            errors += await RunDomainAsync(runId, "performance/deadlocks.sql", async () =>
            {
                var rows = await _source.ReadDeadlocksAsync(token); LogRows("performance/deadlocks.sql", rows.Count);
                _logger.LogInformation("DeadlockEvents {Count} new rows inserted", await _store.InsertDeadlocksAsync(rows, serverId, databaseIds, performanceCapturedAtUtc, token));
                _logger.LogInformation("Deadlock operational events correlated: {Count}", await _store.UpsertOperationalEventsAsync(_correlator.Deadlocks(rows, serverId, performanceCapturedAtUtc), performanceCapturedAtUtc, token));
            }, token);
            if (errors == 0)
            {
                try
                {
                    var anomalies = await _anomalyEngine.EvaluateAsync(DateTime.UtcNow, token);
                    var events = anomalies.Select(ToOperationalEvent).ToArray();
                    if (events.Length > 0) await _store.UpsertOperationalEventsAsync(events, DateTime.UtcNow, token);
                    foreach (var eventType in new[] { "PerformanceAnomaly", "JobDurationAnomaly", "BackupDurationAnomaly", "GrowthAnomaly" }) await _store.ResolveOperationalEventsAsync(eventType, _anomalyResolveSeconds, DateTime.UtcNow, token);
                    _logger.LogInformation("Anomaly evaluation completed; {Count} active findings", anomalies.Count);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    errors++; _logger.LogError(ex, "Anomaly evaluation failed; raw collection remains available"); await _store.InsertErrorAsync(runId, "baseline/anomaly-evaluation", null, ex.Message, token);
                }
            }
            stopwatch.Stop();
            var status = errors == 0 ? "Success" : "PartialSuccess";
            await _store.CompleteRunAsync(runId, status, DateTime.UtcNow, stopwatch.ElapsedMilliseconds, token);
            _logger.LogInformation("Collection #{RunId} completed; Status: {Status}; Duration: {DurationMs} ms", runId, status, stopwatch.ElapsedMilliseconds);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            stopwatch.Stop();
            _logger.LogError(ex, "Collection #{RunId} failed", runId);
            if (runId != 0)
            {
                await _store.InsertErrorAsync(runId, "collection", null, ex.Message, token);
                await _store.CompleteRunAsync(runId, "Failed", DateTime.UtcNow, stopwatch.ElapsedMilliseconds, token);
            }
        }
    }

    private async Task<int> RunDomainAsync(long runId, string queryName, Func<Task> action, CancellationToken token)
    {
        try { await action(); return 0; }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogError(ex, "{QueryName} failed; continuing collection", queryName);
            await _store.InsertErrorAsync(runId, queryName, null, ex.Message, token);
            return 1;
        }
    }

    private void LogRows(string query, int count) => _logger.LogInformation("{QueryName} OK - {Count} rows", query, count);
    private static OperationalEventInput ToOperationalEvent(AnomalyEvaluation finding)
    {
        var eventType = finding.MetricType switch { "JobDuration" => "JobDurationAnomaly", "BackupDuration" => "BackupDurationAnomaly", "DatabaseGrowth" => "GrowthAnomaly", _ => "PerformanceAnomaly" };
        var title = $"{finding.MetricType} anomaly";
        var summary = $"Observed {finding.ObservedValue:0.##}; historical median {finding.BaselineMedian:0.##}, P95 {finding.BaselineP95:0.##}. {finding.ExplanationCode}.";
        return new(eventType, finding.ServerId, finding.DatabaseId, finding.Fingerprint, finding.ObservedAtUtc, finding.ObservedAtUtc, 0, finding.Status, finding.Severity, 1, null, title, summary, finding.SourceEntityId, $"{{\"metricType\":\"{finding.MetricType}\",\"baselineScope\":\"{finding.BaselineScope}\",\"sampleCount\":{finding.SampleCount}}}");
    }
    private static DataTable Table(params (string Name, Type Type)[] columns) { var t = new DataTable(); foreach (var c in columns) t.Columns.Add(c.Name, c.Type); return t; }
    private static object Db(object? value) => value ?? DBNull.Value;
    private static object Db(IReadOnlyDictionary<string, int> values, string key) => values.TryGetValue(key, out var id) ? id : DBNull.Value;
}
