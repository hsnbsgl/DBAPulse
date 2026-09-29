using System.Security.Cryptography;
using System.Text;
using DBAPulse.Domain;

namespace DBAPulse.Collector;

public sealed class OperationalEventCorrelator
{
    private readonly long _blockingWarningMs, _blockingCriticalMs, _longWarningMs, _longCriticalMs;
    private readonly string _deadlockSeverity;
    private readonly long _backupDataWarningMs, _backupDataCriticalMs, _backupLogWarningMs, _backupLogCriticalMs;
    public OperationalEventCorrelator(IConfiguration configuration)
    {
        _blockingWarningMs = Seconds(configuration, "DBAPULSE_BLOCKING_WARNING_SECONDS", 30);
        _blockingCriticalMs = Seconds(configuration, "DBAPULSE_BLOCKING_CRITICAL_SECONDS", 120);
        _longWarningMs = Seconds(configuration, "DBAPULSE_LONGRUNNING_WARNING_SECONDS", 60);
        _longCriticalMs = Seconds(configuration, "DBAPULSE_LONGRUNNING_CRITICAL_SECONDS", 300);
        var configuredSeverity = configuration["DBAPULSE_DEADLOCK_DEFAULT_SEVERITY"];
        _deadlockSeverity = configuredSeverity is "Info" or "Warning" or "Critical" ? configuredSeverity : "Warning";
        _backupDataWarningMs = Seconds(configuration, "DBAPULSE_BACKUP_FULL_WARNING_HOURS", 19) * 3600;
        _backupDataCriticalMs = Seconds(configuration, "DBAPULSE_BACKUP_FULL_CRITICAL_HOURS", 24) * 3600;
        _backupLogWarningMs = Seconds(configuration, "DBAPULSE_BACKUP_LOG_WARNING_MINUTES", 45) * 60;
        _backupLogCriticalMs = Seconds(configuration, "DBAPULSE_BACKUP_LOG_CRITICAL_MINUTES", 60) * 60;
    }

    public IReadOnlyList<OperationalEventInput> Blocking(IEnumerable<BlockingInventory> rows, int serverId, IReadOnlyDictionary<string, int> databaseIds, DateTime capturedAtUtc)
        => rows.GroupBy(r => Fingerprint("Blocking", serverId, databaseIds.TryGetValue(r.DatabaseName ?? string.Empty, out var id) ? id : 0, r.BlockingSessionId, r.SessionId, r.SqlTextHash))
            .Select(g => { var r = g.OrderByDescending(x => x.WaitDurationMs).First(); var db = databaseIds.TryGetValue(r.DatabaseName ?? string.Empty, out var id) ? id : (int?)null; return new OperationalEventInput("Blocking", serverId, db, g.Key, capturedAtUtc, capturedAtUtc, r.WaitDurationMs, "Active", Severity(r.WaitDurationMs, _blockingWarningMs, _blockingCriticalMs), g.Count(), 1, $"Blocking on {r.DatabaseName ?? "server"}", $"Session {r.BlockingSessionId} blocked session {r.SessionId}.", null, null); }).ToArray();

    public IReadOnlyList<OperationalEventInput> LongRunning(IEnumerable<LongRunningInventory> rows, int serverId, IReadOnlyDictionary<string, int> databaseIds, DateTime capturedAtUtc)
        => rows.GroupBy(r => Fingerprint("LongRunning", serverId, databaseIds.TryGetValue(r.DatabaseName ?? string.Empty, out var id) ? id : 0, r.SessionId, r.SqlTextHash, r.RequestStartTimeSource?.ToString("O")))
            .Select(g => { var r = g.OrderByDescending(x => x.ElapsedMs).First(); var db = databaseIds.TryGetValue(r.DatabaseName ?? string.Empty, out var id) ? id : (int?)null; return new OperationalEventInput("LongRunning", serverId, db, g.Key, capturedAtUtc, capturedAtUtc, r.ElapsedMs, "Active", Severity(r.ElapsedMs, _longWarningMs, _longCriticalMs), g.Count(), 1, $"Long-running request on {r.DatabaseName ?? "server"}", $"Session {r.SessionId} has been running for {r.ElapsedMs / 1000} seconds.", null, null); }).ToArray();

    public IReadOnlyList<OperationalEventInput> Deadlocks(IEnumerable<DeadlockInventory> rows, int serverId, DateTime collectedAtUtc)
        => rows.Select(r => new OperationalEventInput("Deadlock", serverId, null, r.DeadlockHash, r.OccurredAt, r.OccurredAt, 0, "Resolved", _deadlockSeverity, 1, null, "Deadlock detected", $"Deadlock with {r.ProcessCount} processes.", null, null)).ToArray();

    public IReadOnlyList<OperationalEventInput> BackupProtection(IEnumerable<DatabaseInventory> databases, IEnumerable<BackupInventory> backups, int serverId, IReadOnlyDictionary<string, int> databaseIds, DateTime capturedAtUtc)
    {
        var latest = backups.GroupBy(x => $"{x.DatabaseName}|{x.BackupType}", StringComparer.OrdinalIgnoreCase).ToDictionary(x => x.Key, x => x.OrderByDescending(y => y.BackupFinish).First(), StringComparer.OrdinalIgnoreCase);
        var result = new List<OperationalEventInput>();
        foreach (var db in databases.Where(x => !x.DatabaseName.Equals("tempdb", StringComparison.OrdinalIgnoreCase) && x.DatabaseStatus.Equals("ONLINE", StringComparison.OrdinalIgnoreCase)))
        {
            var full = latest.TryGetValue($"{db.DatabaseName}|FULL", out var f) ? f.BackupFinish : null;
            var differential = latest.TryGetValue($"{db.DatabaseName}|DIFFERENTIAL", out var d) ? d.BackupFinish : null;
            var log = latest.TryGetValue($"{db.DatabaseName}|LOG", out var l) ? l.BackupFinish : null;
            var dataBackup = full.HasValue && (!differential.HasValue || full.Value >= differential.Value) ? full : differential;
            var dataBackupMinutes = dataBackup.HasValue ? Math.Max(0, (DateTime.UtcNow - dataBackup.Value).TotalMinutes) : double.MaxValue;
            var logMinutes = log.HasValue ? Math.Max(0, (DateTime.UtcNow - log.Value).TotalMinutes) : double.MaxValue;
            var critical = !dataBackup.HasValue || dataBackupMinutes * 60000 >= _backupDataCriticalMs || (db.RecoveryModel is "FULL" or "BULK_LOGGED" && (!log.HasValue || logMinutes * 60000 >= _backupLogCriticalMs));
            var warning = !critical && (dataBackupMinutes * 60000 >= _backupDataWarningMs || (db.RecoveryModel is "FULL" or "BULK_LOGGED" && logMinutes * 60000 >= _backupLogWarningMs));
            if (!critical && !warning) continue;
            var id = databaseIds.TryGetValue(db.DatabaseName, out var databaseId) ? databaseId : (int?)null;
            var fingerprint = Fingerprint("BackupProtection", serverId, id, "Default");
            var backupType = differential.HasValue && (!full.HasValue || differential.Value > full.Value) ? "differential" : "full";
            result.Add(new OperationalEventInput("BackupProtection", serverId, id, fingerprint, capturedAtUtc, capturedAtUtc, (long)Math.Max(0, dataBackupMinutes * 60000), "Active", critical ? "Critical" : "Warning", 1, null, $"Backup protection on {db.DatabaseName}", dataBackup.HasValue ? $"Last {backupType} backup is {Math.Round(dataBackupMinutes / 60, 1)} hours old." : "No full or differential backup has been recorded.", null, null));
        }
        return result;
    }

    public IReadOnlyList<OperationalEventInput> JobFailures(IEnumerable<JobInventory> jobs, int serverId, DateTime capturedAtUtc)
        => jobs.Where(x => x.Enabled && x.LastRunStatus == "Failed").Select(x => new OperationalEventInput("JobFailure", serverId, null, Fingerprint("JobFailure", serverId, x.JobId, x.LastRunAtSource?.ToString("O")), capturedAtUtc, capturedAtUtc, (x.LastRunDurationSeconds ?? 0) * 1000L, "Active", x.RepeatedFailure ? "Critical" : "Warning", 1, null, $"Job failure: {x.JobName}", $"Job has failed {x.FailureCount24Hours} time(s) in the last 24 hours.", null, null)).ToArray();

    public IReadOnlyList<OperationalEventInput> AlwaysOnHealth(IEnumerable<AlwaysOnInventory> rows, int serverId, DateTime capturedAtUtc)
        => rows.Where(x => x.IsSuspended || string.Equals(x.ConnectedState, "DISCONNECTED", StringComparison.OrdinalIgnoreCase) || string.Equals(x.SynchronizationHealth, "NOT_HEALTHY", StringComparison.OrdinalIgnoreCase) || string.Equals(x.SynchronizationHealth, "PARTIALLY_HEALTHY", StringComparison.OrdinalIgnoreCase)).Select(x => { var critical = x.IsSuspended || string.Equals(x.ConnectedState, "DISCONNECTED", StringComparison.OrdinalIgnoreCase) || string.Equals(x.SynchronizationHealth, "NOT_HEALTHY", StringComparison.OrdinalIgnoreCase); var fp = Fingerprint("AlwaysOnHealth", serverId, x.AvailabilityGroupName, x.ReplicaServerName, x.DatabaseName); return new OperationalEventInput("AlwaysOnHealth", serverId, null, fp, capturedAtUtc, capturedAtUtc, 0, "Active", critical ? "Critical" : "Warning", 1, null, $"Always On health on {x.AvailabilityGroupName}", $"Replica {x.ReplicaServerName ?? "unknown"} reported {x.SynchronizationHealth ?? "unknown"}.", null, null); }).ToArray();

    public int BlockingResolveSeconds(IConfiguration c) => Int(c, "DBAPULSE_BLOCKING_RESOLVE_AFTER_SECONDS", 180);
    public int LongRunningResolveSeconds(IConfiguration c) => Int(c, "DBAPULSE_LONGRUNNING_RESOLVE_AFTER_SECONDS", 180);
    private static string Severity(long durationMs, long warning, long critical) => durationMs >= critical ? "Critical" : durationMs >= warning ? "Warning" : "Info";
    private static string Fingerprint(params object?[] values) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("|", values.Select(x => x?.ToString() ?? ""))))).ToLowerInvariant();
    private static long Seconds(IConfiguration c, string key, int fallback) => Math.Max(1, Int(c, key, fallback)) * 1000L;
    private static int Int(IConfiguration c, string key, int fallback) => int.TryParse(c[key], out var value) ? Math.Max(1, value) : fallback;
}
