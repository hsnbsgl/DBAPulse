using System.Data;
using Microsoft.Data.SqlClient;
using DBAPulse.Domain;

namespace DBAPulse.Collector;

public sealed class SourceQueryClient
{
    private readonly string _connectionString;
    private readonly string _queryRoot;
    public SourceQueryClient(string connectionString, string queryRoot) { _connectionString = connectionString; _queryRoot = queryRoot; }

    public Task<List<ServerInventory>> ReadServersAsync(CancellationToken token) => QueryAsync("inventory/server-info.sql", ReadServer, token);
    public Task<List<DatabaseInventory>> ReadDatabasesAsync(CancellationToken token) => QueryAsync("inventory/databases.sql", ReadDatabase, token);
    public Task<List<BackupInventory>> ReadBackupsAsync(CancellationToken token) => QueryAsync("backup/last-backups.sql", ReadBackup, token);
    public Task<List<JobInventory>> ReadJobsAsync(CancellationToken token) => QueryAsync("jobs/job-status.sql", ReadJob, token);
    public Task<List<AlwaysOnInventory>> ReadAlwaysOnAsync(CancellationToken token) => QueryAsync("alwayson/ag-health.sql", ReadAlwaysOn, token).ContinueWith(t => t.Result.Where(x => !string.Equals(x.AvailabilityGroupName, "NotConfigured", StringComparison.OrdinalIgnoreCase)).ToList(), token);
    public Task<List<CapacityInventory>> ReadCapacityAsync(CancellationToken token) => QueryAsync("capacity/database-size.sql", ReadCapacity, token);
    public Task<List<VolumeInventory>> ReadVolumesAsync(CancellationToken token) => QueryAsync("capacity/volumes.sql", ReadVolume, token);
    public Task<List<BlockingInventory>> ReadBlockingAsync(CancellationToken token) => QueryAsync("performance/blocking.sql", ReadBlocking, token);
    public Task<List<LongRunningInventory>> ReadLongRunningAsync(long thresholdMs, CancellationToken token) => QueryAsync("performance/long-running-requests.sql", ReadLongRunning, token, sql => sql.Replace("{LONG_RUNNING_MS}", thresholdMs.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal));
    public Task<List<WaitStatsInventory>> ReadWaitStatsAsync(CancellationToken token) => QueryAsync("performance/wait-stats.sql", ReadWaitStats, token);
    public Task<List<DeadlockInventory>> ReadDeadlocksAsync(CancellationToken token) => QueryAsync("performance/deadlocks.sql", ReadDeadlock, token);

    private async Task<List<T>> QueryAsync<T>(string relativePath, Func<SqlDataReader, T?> mapper, CancellationToken token, Func<string, string>? transform = null) where T : class
    {
        var result = new List<T>();
        var sql = await File.ReadAllTextAsync(Path.Combine(_queryRoot, relativePath), token);
        if (transform is not null) sql = transform(sql);
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand(sql, connection) { CommandType = CommandType.Text, CommandTimeout = 120 };
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            var item = mapper(reader);
            if (item is not null) result.Add(item);
        }
        return result;
    }

    private static ServerInventory ReadServer(SqlDataReader r) => new(S(r, "server_name"), S(r, "instance_name"), S(r, "product_version"), S(r, "edition"), L(r, "uptime_seconds"));
    private static DatabaseInventory ReadDatabase(SqlDataReader r) => new(S(r, "database_name"), S(r, "recovery_model_desc"), S(r, "state_desc"), S(r, "user_access_desc"), I(r, "compatibility_level"), B(r, "is_read_only"), B(r, "is_encrypted"));
    private static BackupInventory ReadBackup(SqlDataReader r) => new(S(r, "database_name"), S(r, "backup_type"), D(r, "backup_start_date"), D(r, "backup_finish_date"), Dec(r, "backup_size_mb"), Dec(r, "compressed_backup_size_mb"), B(r, "is_copy_only"), INullable(r, "duration_seconds"));
    private static JobInventory ReadJob(SqlDataReader r) => new(S(r, "job_id"), S(r, "job_name"), B(r, "enabled"), S(r, "last_run_status"), JobDate(r), INullable(r, "last_run_duration_seconds"), SNullable(r, "last_run_message"), B(r, "is_running"), D(r, "current_start_at_source"), INullable(r, "current_duration_seconds"), D(r, "next_run_at_source"), I(r, "failure_count_24h"), I(r, "failure_count_7d"), B(r, "repeated_failure"), INullable(r, "average_duration_seconds"), INullable(r, "max_duration_seconds"));
    private static AlwaysOnInventory ReadAlwaysOn(SqlDataReader r) => new(SNullable(r, "availability_group_name") ?? SNullable(r, "status") ?? "NotConfigured", SNullable(r, "replica_server_name"), SNullable(r, "role_desc"), SNullable(r, "operational_state_desc"), SNullable(r, "connected_state_desc"), SNullable(r, "synchronization_health_desc"), SNullable(r, "database_name"), SNullable(r, "synchronization_state_desc"), SNullable(r, "database_state_desc"), B(r, "is_suspended"), SNullable(r, "suspend_reason"), DecNullable(r, "log_send_queue_mb"), DecNullable(r, "redo_queue_mb"), DecNullable(r, "log_send_rate_mb"), DecNullable(r, "redo_rate_mb"), D(r, "last_commit_time_source"));
    private static CapacityInventory ReadCapacity(SqlDataReader r) => new(S(r, "database_name"), S(r, "file_type"), Dec(r, "allocated_size_mb") ?? 0, I(r, "file_count"));
    private static VolumeInventory ReadVolume(SqlDataReader r) => new(S(r, "volume_id"), L(r, "total_bytes") ?? 0, L(r, "available_bytes") ?? 0);
    private static BlockingInventory ReadBlocking(SqlDataReader r) => new(I(r, "session_id"), I(r, "blocking_session_id"), N(r, "database_name"), N(r, "wait_type"), L(r, "wait_duration_ms") ?? 0, N(r, "command_name"), N(r, "host_name"), N(r, "application_name"), N(r, "login_name"), N(r, "sql_text_hash"), N(r, "sql_text_preview"));
    private static LongRunningInventory ReadLongRunning(SqlDataReader r) => new(I(r, "session_id"), N(r, "database_name"), D(r, "request_start_time"), L(r, "elapsed_ms") ?? 0, N(r, "status"), N(r, "command_name"), N(r, "wait_type"), L(r, "wait_time_ms"), L(r, "cpu_time_ms"), L(r, "logical_reads"), L(r, "reads"), L(r, "writes"), N(r, "host_name"), N(r, "application_name"), N(r, "login_name"), N(r, "sql_text_hash"), N(r, "sql_text_preview"));
    private static WaitStatsInventory ReadWaitStats(SqlDataReader r) => new(S(r, "wait_type"), L(r, "wait_time_ms") ?? 0, L(r, "signal_wait_time_ms") ?? 0, L(r, "waiting_tasks_count") ?? 0, D(r, "sql_server_start_time") ?? DateTime.UtcNow);
    private static DeadlockInventory ReadDeadlock(SqlDataReader r) => new(D(r, "occurred_at") ?? DateTime.UtcNow, N(r, "victim_process_id"), I(r, "process_count"), S(r, "deadlock_hash"), S(r, "deadlock_xml"));

    private static DateTime? JobDate(SqlDataReader r)
    {
        if (r.IsDBNull(r.GetOrdinal("run_date"))) return null;
        var date = r.GetInt32(r.GetOrdinal("run_date")); var time = r.IsDBNull(r.GetOrdinal("run_time")) ? 0 : r.GetInt32(r.GetOrdinal("run_time"));
        return DateTime.TryParseExact($"{date:00000000}{time:000000}", "yyyyMMddHHmmss", null, System.Globalization.DateTimeStyles.None, out var value) ? value : null;
    }
    private static int Ord(SqlDataReader r, string name) => r.GetOrdinal(name);
    private static string S(SqlDataReader r, string name) => r.IsDBNull(Ord(r, name)) ? string.Empty : Convert.ToString(r.GetValue(Ord(r, name))) ?? string.Empty;
    private static string? SNullable(SqlDataReader r, string name) => Has(r, name) && !r.IsDBNull(Ord(r, name)) ? Convert.ToString(r.GetValue(Ord(r, name))) : null;
    private static int I(SqlDataReader r, string name) => r.IsDBNull(Ord(r, name)) ? 0 : Convert.ToInt32(r.GetValue(Ord(r, name)));
    private static int? INullable(SqlDataReader r, string name) => Has(r, name) && !r.IsDBNull(Ord(r, name)) ? Convert.ToInt32(r.GetValue(Ord(r, name))) : null;
    private static long? L(SqlDataReader r, string name) => Has(r, name) && !r.IsDBNull(Ord(r, name)) ? Convert.ToInt64(r.GetValue(Ord(r, name))) : null;
    private static bool B(SqlDataReader r, string name) => !Has(r, name) || r.IsDBNull(Ord(r, name)) ? false : Convert.ToBoolean(r.GetValue(Ord(r, name)));
    private static DateTime? D(SqlDataReader r, string name) => !Has(r, name) || r.IsDBNull(Ord(r, name)) ? null : Convert.ToDateTime(r.GetValue(Ord(r, name)));
    private static decimal? Dec(SqlDataReader r, string name) => !Has(r, name) || r.IsDBNull(Ord(r, name)) ? null : Convert.ToDecimal(r.GetValue(Ord(r, name)));
    private static decimal? DecNullable(SqlDataReader r, string name) => Has(r, name) && !r.IsDBNull(Ord(r, name)) ? Convert.ToDecimal(r.GetValue(Ord(r, name))) : null;
    private static string? N(SqlDataReader r, string name) => Has(r, name) && !r.IsDBNull(Ord(r, name)) ? Convert.ToString(r.GetValue(Ord(r, name))) : null;
    private static bool Has(SqlDataReader r, string name) { try { _ = r.GetOrdinal(name); return true; } catch (IndexOutOfRangeException) { return false; } }
}
