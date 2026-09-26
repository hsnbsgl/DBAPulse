using System.Data;
using Microsoft.Data.SqlClient;
using DBAPulse.Domain;

namespace DBAPulse.Data;

public sealed class ManagementStore
{
    private readonly string _connectionString;
    public ManagementStore(SqlOptions options) => _connectionString = new SqlConnectionStringBuilder(options.ManagementConnectionString) { InitialCatalog = "DBA_PULSE" }.ConnectionString;

    public async Task<long> StartRunAsync(DateTime utcNow, CancellationToken token)
    {
        await using var connection = await OpenAsync(token);
        await using var command = Procedure(connection, "dbo.usp_CollectionRun_Start");
        command.Parameters.Add(new SqlParameter("@StartedAtUtc", SqlDbType.DateTime2) { Value = utcNow });
        return Convert.ToInt64(await command.ExecuteScalarAsync(token));
    }

    public async Task CompleteRunAsync(long id, string status, DateTime utcNow, long durationMs, CancellationToken token)
    {
        await using var connection = await OpenAsync(token);
        await using var command = Procedure(connection, "dbo.usp_CollectionRun_Complete");
        command.Parameters.AddWithValue("@CollectionRunId", id);
        command.Parameters.AddWithValue("@Status", status);
        command.Parameters.Add(new SqlParameter("@FinishedAtUtc", SqlDbType.DateTime2) { Value = utcNow });
        command.Parameters.AddWithValue("@DurationMs", durationMs);
        await command.ExecuteNonQueryAsync(token);
    }

    public async Task InsertErrorAsync(long runId, string queryName, string? serverName, string message, CancellationToken token)
    {
        await using var connection = await OpenAsync(token);
        await using var command = Procedure(connection, "dbo.usp_CollectionError_Insert");
        command.Parameters.AddWithValue("@CollectionRunId", runId);
        command.Parameters.AddWithValue("@QueryName", queryName);
        command.Parameters.AddWithValue("@ServerName", (object?)serverName ?? DBNull.Value);
        command.Parameters.AddWithValue("@ErrorMessage", message.Length > 4000 ? message[..4000] : message);
        await command.ExecuteNonQueryAsync(token);
    }

    public async Task<Dictionary<string, int>> SyncServersAsync(IReadOnlyCollection<ServerInput> rows, CancellationToken token)
    {
        var table = new DataTable();
        table.Columns.Add("ServerName", typeof(string)); table.Columns.Add("InstanceName", typeof(string));
        table.Columns.Add("SqlVersion", typeof(string)); table.Columns.Add("Edition", typeof(string));
        table.Columns.Add("TimeZoneId", typeof(string)); table.Columns.Add("LastSeenAtUtc", typeof(DateTime)); table.Columns.Add("IsActive", typeof(bool));
        foreach (var r in rows) table.Rows.Add(r.ServerName, r.InstanceName, r.SqlVersion, r.Edition, r.TimeZoneId, r.LastSeenAtUtc.UtcDateTime, r.IsActive);
        return await SyncMapAsync("dbo.usp_Servers_Sync", "dbo.ServerInputType", table, "ServerName", token);
    }

    public async Task<(int CollectionIntervalMinutes, int CapacityIntervalMinutes)> GetServerIntervalsAsync(int serverId, CancellationToken token)
    {
        await using var connection = await OpenAsync(token);
        await using var command = new SqlCommand("SELECT CollectionIntervalMinutes,CapacityIntervalMinutes FROM dbo.Servers WHERE Id=@ServerId", connection);
        command.Parameters.AddWithValue("@ServerId", serverId);
        await using var reader = await command.ExecuteReaderAsync(token);
        return await reader.ReadAsync(token) ? (reader.GetInt32(0), reader.GetInt32(1)) : (5, 60);
    }
    public async Task<bool> IsServerActiveAsync(int serverId, CancellationToken token)
    {
        await using var connection = await OpenAsync(token);
        await using var command = new SqlCommand("SELECT IsActive FROM dbo.Servers WHERE Id=@ServerId", connection);
        command.Parameters.AddWithValue("@ServerId", serverId);
        var value = await command.ExecuteScalarAsync(token);
        return value is not null && value is not DBNull && Convert.ToBoolean(value);
    }

    public async Task<Dictionary<string, int>> SyncDatabasesAsync(IReadOnlyCollection<DatabaseInput> rows, CancellationToken token)
    {
        var table = new DataTable();
        table.Columns.Add("ServerId", typeof(int)); table.Columns.Add("DatabaseName", typeof(string));
        table.Columns.Add("RecoveryModel", typeof(string)); table.Columns.Add("DatabaseStatus", typeof(string));
        table.Columns.Add("LastSeenAtUtc", typeof(DateTime)); table.Columns.Add("IsActive", typeof(bool));
        foreach (var r in rows) table.Rows.Add(r.ServerId, r.DatabaseName, r.RecoveryModel, r.DatabaseStatus, r.LastSeenAtUtc.UtcDateTime, r.IsActive);
        return await SyncMapAsync("dbo.usp_Databases_Sync", "dbo.DatabaseInputType", table, "DatabaseName", token);
    }

    public Task<int> InsertServerSnapshotsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_ServerSnapshots_Insert", "dbo.ServerSnapshotInputType", rows, token);
    public Task<int> InsertDatabaseSnapshotsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_DatabaseSnapshots_Insert", "dbo.DatabaseSnapshotInputType", rows, token);
    public Task<int> InsertBackupSnapshotsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_BackupSnapshots_Insert", "dbo.BackupSnapshotInputType", rows, token);
    public Task<int> InsertJobSnapshotsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_JobSnapshots_Insert", "dbo.JobSnapshotInputType", rows, token);
    public Task<int> InsertAlwaysOnSnapshotsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_AlwaysOnSnapshots_Insert", "dbo.AlwaysOnSnapshotInputType", rows, token);
    public Task<int> InsertProtectionBackupsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_BackupProtectionSnapshots_Insert", "dbo.BackupProtectionSnapshotInputType", rows, token);
    public Task<int> InsertProtectionJobsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_JobHealthSnapshots_Insert", "dbo.JobHealthSnapshotInputType", rows, token);
    public Task<int> InsertProtectionAlwaysOnAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_AlwaysOnTelemetry_Insert", "dbo.AlwaysOnTelemetryInputType", rows, token);
    public Task<int> InsertCapacitySnapshotsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_CapacitySnapshots_Insert", "dbo.CapacitySnapshotInputType", rows, token);
    public Task<int> InsertVolumeCapacitySnapshotsAsync(DataTable rows, CancellationToken token) => InsertAsync("dbo.usp_VolumeCapacitySnapshots_Insert", "dbo.VolumeCapacitySnapshotInputType", rows, token);

    public Task<int> InsertBlockingAsync(IEnumerable<BlockingInventory> rows, long runId, int serverId, IReadOnlyDictionary<string, int> databaseIds, DateTime capturedAtUtc, CancellationToken token)
    {
        var table = Table(("ServerId", typeof(int)), ("DatabaseId", typeof(int)), ("CapturedAtUtc", typeof(DateTime)), ("SessionId", typeof(int)), ("BlockingSessionId", typeof(int)), ("WaitType", typeof(string)), ("WaitDurationMs", typeof(long)), ("Command", typeof(string)), ("HostName", typeof(string)), ("ApplicationName", typeof(string)), ("LoginName", typeof(string)), ("SqlTextHash", typeof(string)), ("SqlTextPreview", typeof(string)));
        foreach (var r in rows) table.Rows.Add(serverId, Db(databaseIds, r.DatabaseName), capturedAtUtc, r.SessionId, r.BlockingSessionId, Db(r.WaitType), r.WaitDurationMs, Db(r.Command), Db(r.HostName), Db(r.ApplicationName), Db(r.LoginName), Db(r.SqlTextHash), Db(r.SqlTextPreview));
        return InsertAsync("dbo.usp_BlockingEvents_Insert", "dbo.BlockingEventInputType", table, token);
    }

    public Task<int> InsertLongRunningAsync(IEnumerable<LongRunningInventory> rows, int serverId, IReadOnlyDictionary<string, int> databaseIds, DateTime capturedAtUtc, CancellationToken token)
    {
        var table = Table(("ServerId", typeof(int)), ("DatabaseId", typeof(int)), ("CapturedAtUtc", typeof(DateTime)), ("SessionId", typeof(int)), ("RequestStartTimeSource", typeof(DateTime)), ("ElapsedMs", typeof(long)), ("Status", typeof(string)), ("Command", typeof(string)), ("WaitType", typeof(string)), ("WaitTimeMs", typeof(long)), ("CpuTimeMs", typeof(long)), ("LogicalReads", typeof(long)), ("Reads", typeof(long)), ("Writes", typeof(long)), ("HostName", typeof(string)), ("ApplicationName", typeof(string)), ("LoginName", typeof(string)), ("SqlTextHash", typeof(string)), ("SqlTextPreview", typeof(string)));
        foreach (var r in rows) table.Rows.Add(serverId, Db(databaseIds, r.DatabaseName), capturedAtUtc, r.SessionId, Db(r.RequestStartTimeSource), r.ElapsedMs, Db(r.Status), Db(r.Command), Db(r.WaitType), Db(r.WaitTimeMs), Db(r.CpuTimeMs), Db(r.LogicalReads), Db(r.Reads), Db(r.Writes), Db(r.HostName), Db(r.ApplicationName), Db(r.LoginName), Db(r.SqlTextHash), Db(r.SqlTextPreview));
        return InsertAsync("dbo.usp_LongRunningRequests_Insert", "dbo.LongRunningRequestInputType", table, token);
    }

    public Task<int> InsertWaitStatsAsync(IEnumerable<WaitStatsInventory> rows, int serverId, DateTime capturedAtUtc, CancellationToken token)
    {
        var table = Table(("ServerId", typeof(int)), ("CapturedAtUtc", typeof(DateTime)), ("SqlServerStartTimeUtc", typeof(DateTime)), ("WaitType", typeof(string)), ("WaitTimeMs", typeof(long)), ("SignalWaitTimeMs", typeof(long)), ("WaitingTasksCount", typeof(long)));
        foreach (var r in rows) table.Rows.Add(serverId, capturedAtUtc, r.SqlServerStartTime, r.WaitType, r.WaitTimeMs, r.SignalWaitTimeMs, r.WaitingTasksCount);
        return InsertAsync("dbo.usp_WaitStatsSnapshots_Insert", "dbo.WaitStatsSnapshotInputType", table, token);
    }

    public Task<int> InsertDeadlocksAsync(IEnumerable<DeadlockInventory> rows, int serverId, IReadOnlyDictionary<string, int> databaseIds, DateTime collectedAtUtc, CancellationToken token)
    {
        var table = Table(("ServerId", typeof(int)), ("DatabaseId", typeof(int)), ("OccurredAtUtc", typeof(DateTime)), ("VictimProcessId", typeof(string)), ("VictimSessionId", typeof(int)), ("ProcessCount", typeof(int)), ("DeadlockHash", typeof(string)), ("DeadlockXml", typeof(string)), ("CollectedAtUtc", typeof(DateTime)));
        foreach (var r in rows) table.Rows.Add(serverId, DBNull.Value, r.OccurredAt, Db(r.VictimProcessId), DBNull.Value, r.ProcessCount, r.DeadlockHash, r.DeadlockXml, collectedAtUtc);
        return InsertAsync("dbo.usp_DeadlockEvents_Insert", "dbo.DeadlockEventInputType", table, token);
    }

    public Task<int> UpsertOperationalEventsAsync(IEnumerable<OperationalEventInput> rows, DateTime asOfUtc, CancellationToken token)
    {
        var table = Table(("EventType", typeof(string)), ("ServerId", typeof(int)), ("DatabaseId", typeof(int)), ("Fingerprint", typeof(string)), ("StartedAtUtc", typeof(DateTime)), ("LastSeenAtUtc", typeof(DateTime)), ("DurationMs", typeof(long)), ("Status", typeof(string)), ("Severity", typeof(string)), ("ObservationIncrement", typeof(int)), ("AffectedSessionCount", typeof(int)), ("Title", typeof(string)), ("Summary", typeof(string)), ("SourceEntityId", typeof(long)), ("AdditionalData", typeof(string)));
        foreach (var r in rows) table.Rows.Add(r.EventType, r.ServerId, Db(r.DatabaseId), r.Fingerprint, r.StartedAtUtc, r.LastSeenAtUtc, r.DurationMs, r.Status, r.Severity, r.ObservationIncrement, Db(r.AffectedSessionCount), r.Title, r.Summary, Db(r.SourceEntityId), Db(r.AdditionalData));
        if (table.Rows.Count == 0) return Task.FromResult(0);
        return ExecuteOperationalAsync("dbo.usp_OperationalEvents_Upsert", table, asOfUtc, token);
    }

    public async Task<int> ResolveOperationalEventsAsync(string eventType, int afterSeconds, DateTime asOfUtc, CancellationToken token)
    {
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, "dbo.usp_OperationalEvents_ResolveStale");
        command.Parameters.AddWithValue("@EventType", eventType); command.Parameters.AddWithValue("@AfterSeconds", afterSeconds); command.Parameters.Add(new SqlParameter("@AsOfUtc", SqlDbType.DateTime2) { Value = asOfUtc });
        return Convert.ToInt32(await command.ExecuteScalarAsync(token));
    }

    private async Task<int> ExecuteOperationalAsync(string procedure, DataTable table, DateTime asOfUtc, CancellationToken token)
    {
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, procedure);
        command.Parameters.Add(new SqlParameter("@Rows", SqlDbType.Structured) { TypeName = "dbo.OperationalEventInputType", Value = table });
        command.Parameters.Add(new SqlParameter("@AsOfUtc", SqlDbType.DateTime2) { Value = asOfUtc });
        return Convert.ToInt32(await command.ExecuteScalarAsync(token));
    }

    private static DataTable Table(params (string Name, Type Type)[] columns) { var t = new DataTable(); foreach (var c in columns) t.Columns.Add(c.Name, c.Type); return t; }
    private static object Db(object? value) => value ?? DBNull.Value;
    private static object Db(IReadOnlyDictionary<string, int> values, string? key) => key is not null && values.TryGetValue(key, out var id) ? id : DBNull.Value;

    private async Task<Dictionary<string, int>> SyncMapAsync(string procedure, string typeName, DataTable table, string key, CancellationToken token)
    {
        var result = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        if (table.Rows.Count == 0) return result;
        await using var connection = await OpenAsync(token);
        await using var command = Procedure(connection, procedure);
        command.Parameters.Add(new SqlParameter("@Rows", SqlDbType.Structured) { TypeName = typeName, Value = table });
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token)) result[reader.GetString(reader.GetOrdinal(key))] = reader.GetInt32(reader.GetOrdinal("Id"));
        return result;
    }

    private async Task<int> InsertAsync(string procedure, string typeName, DataTable table, CancellationToken token)
    {
        if (table.Rows.Count == 0) return 0;
        await using var connection = await OpenAsync(token);
        await using var command = Procedure(connection, procedure);
        command.Parameters.Add(new SqlParameter("@Rows", SqlDbType.Structured) { TypeName = typeName, Value = table });
        return Convert.ToInt32(await command.ExecuteScalarAsync(token));
    }

    private async Task<SqlConnection> OpenAsync(CancellationToken token)
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(token);
        return connection;
    }

    private static SqlCommand Procedure(SqlConnection connection, string name) => new(name, connection) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 };
}
