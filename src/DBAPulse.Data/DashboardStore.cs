using System.Data;
using DBAPulse.Domain;
using Microsoft.Data.SqlClient;

namespace DBAPulse.Data;

public sealed class DashboardStore
{
    private readonly string _connectionString;
    public DashboardStore(string connectionString) => _connectionString = new SqlConnectionStringBuilder(connectionString) { InitialCatalog = "DBA_PULSE" }.ConnectionString;

    public async Task<bool> CanConnectAsync(CancellationToken token)
    {
        await using var connection = await OpenAsync(token);
        await using var command = new SqlCommand("SELECT CAST(1 AS int);", connection);
        return Convert.ToInt32(await command.ExecuteScalarAsync(token)) == 1;
    }

    public async Task<DashboardOverview?> GetOverviewAsync(CancellationToken token) => await OneAsync("dbo.usp_Dashboard_Overview", null, r => new DashboardOverview(I(r, "TotalServers"), I(r, "TotalDatabases"), I(r, "OnlineDatabases"), I(r, "WarningDatabases"), I(r, "OfflineDatabases"), SNullable(r, "LastCollectionStatus"), UtcNullable(r, "LastCollectionStartedAtUtc"), UtcNullable(r, "LastCollectionFinishedAtUtc"), LongNullable(r, "LastCollectionDurationMs"), I(r, "CollectionErrorCount")), token);
    public Task<IReadOnlyList<DatabaseHealthRow>> GetHealthAsync(CancellationToken token) => ManyAsync("dbo.usp_Dashboard_DatabaseHealth", null, r => new DatabaseHealthRow(I(r, "DatabaseId"), S(r, "DatabaseName"), I(r, "ServerId"), S(r, "ServerName"), S(r, "DatabaseStatus"), S(r, "RecoveryModel"), Utc(r, "LastSeenAtUtc"), S(r, "HealthStatus")), token);
    public Task<IReadOnlyList<BackupStatusRow>> GetBackupStatusAsync(CancellationToken token) => ManyAsync("dbo.usp_Dashboard_BackupStatus", null, r => new BackupStatusRow(I(r, "DatabaseId"), S(r, "DatabaseName"), S(r, "ServerName"), S(r, "RecoveryModel"), Date(r, "LastFullBackupAtSource"), Date(r, "LastDifferentialBackupAtSource"), Date(r, "LastLogBackupAtSource"), S(r, "BackupStatus")), token);
    public async Task<(CapacitySummary Summary, IReadOnlyList<CapacityRow> Items)> GetCapacityAsync(CancellationToken token)
    {
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, "dbo.usp_Dashboard_Capacity");
        await using var reader = await command.ExecuteReaderAsync(token);
        CapacitySummary summary = new(0, 0, 0); var items = new List<CapacityRow>();
        if (await reader.ReadAsync(token)) summary = new(Dec(reader, "TotalDataSizeMb"), Dec(reader, "TotalLogSizeMb"), Dec(reader, "TotalDatabaseSizeMb"));
        if (await reader.NextResultAsync(token)) while (await reader.ReadAsync(token)) items.Add(new CapacityRow(I(reader, "DatabaseId"), S(reader, "DatabaseName"), I(reader, "ServerId"), Dec(reader, "DataSizeMb"), Dec(reader, "LogSizeMb"), Dec(reader, "TotalSizeMb"), Utc(reader, "CollectedAtUtc")));
        return (summary, items);
    }
    public Task<IReadOnlyList<RecentCollection>> GetRecentCollectionsAsync(int limit, CancellationToken token) => ManyAsync("dbo.usp_Dashboard_RecentCollections", c => c.Parameters.AddWithValue("@Limit", limit), r => new RecentCollection(Long(r, "CollectionRunId"), Utc(r, "StartedAtUtc"), UtcNullable(r, "FinishedAtUtc"), S(r, "Status"), LongNullable(r, "DurationMs"), I(r, "ErrorCount")), token);
    public Task<IReadOnlyList<ServerListItem>> GetServersAsync(CancellationToken token) => ManyAsync("dbo.usp_Servers_List", null, r => new ServerListItem(I(r, "ServerId"), S(r, "ServerName"), S(r, "InstanceName"), S(r, "SqlVersion"), S(r, "Edition"), I(r, "DatabaseCount"), Utc(r, "LastSeenAtUtc")), token);
    public async Task<ServerDetailResult> GetServerDetailAsync(int id, CancellationToken token)
    {
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, "dbo.usp_Server_Detail"); command.Parameters.AddWithValue("@ServerId", id);
        await using var reader = await command.ExecuteReaderAsync(token); ServerDetail? detail = null; var databases = new List<ServerDatabaseItem>();
        if (await reader.ReadAsync(token)) detail = new(I(reader, "ServerId"), S(reader, "ServerName"), S(reader, "InstanceName"), S(reader, "SqlVersion"), S(reader, "Edition"), S(reader, "TimeZoneId"), Utc(reader, "LastSeenAtUtc"), I(reader, "DatabaseCount"));
        if (await reader.NextResultAsync(token)) while (await reader.ReadAsync(token)) databases.Add(new(I(reader, "DatabaseId"), S(reader, "DatabaseName"), S(reader, "DatabaseStatus"), S(reader, "RecoveryModel"), Utc(reader, "LastSeenAtUtc")));
        return new(detail, databases);
    }
    public async Task<PagedResult<DatabaseListItem>> GetDatabasesAsync(int page, int pageSize, string? search, CancellationToken token)
    {
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, "dbo.usp_Databases_List");
        command.Parameters.AddWithValue("@PageNumber", page); command.Parameters.AddWithValue("@PageSize", pageSize); command.Parameters.AddWithValue("@Search", (object?)search ?? DBNull.Value);
        await using var reader = await command.ExecuteReaderAsync(token); var items = new List<DatabaseListItem>();
        while (await reader.ReadAsync(token)) items.Add(new(I(reader, "DatabaseId"), S(reader, "DatabaseName"), I(reader, "ServerId"), S(reader, "ServerName"), S(reader, "DatabaseStatus"), S(reader, "RecoveryModel"), Utc(reader, "LastSeenAtUtc"), DecNullable(reader, "CurrentDataSizeMb"), DecNullable(reader, "CurrentLogSizeMb"), DecNullable(reader, "CurrentTotalSizeMb"), Date(reader, "LastFullBackupAtSource")));
        var total = 0; if (await reader.NextResultAsync(token) && await reader.ReadAsync(token)) total = I(reader, "TotalCount");
        return new(items, page, pageSize, total);
    }
    public Task<DatabaseDetail?> GetDatabaseDetailAsync(int id, CancellationToken token) => OneAsync("dbo.usp_Database_Detail", c => c.Parameters.AddWithValue("@DatabaseId", id), r => new DatabaseDetail(I(r, "DatabaseId"), S(r, "DatabaseName"), I(r, "ServerId"), S(r, "ServerName"), S(r, "DatabaseStatus"), S(r, "RecoveryModel"), Utc(r, "LastSeenAtUtc"), DecNullable(r, "CurrentDataSizeMb"), DecNullable(r, "CurrentLogSizeMb"), DecNullable(r, "CurrentTotalSizeMb"), Date(r, "LastFullBackupAtSource"), Date(r, "LastDifferentialBackupAtSource"), Date(r, "LastLogBackupAtSource")), token);
    public Task<IReadOnlyList<CapacityHistoryPoint>> GetCapacityHistoryAsync(int id, int days, CancellationToken token) => ManyAsync("dbo.usp_Database_CapacityHistory", c => { c.Parameters.AddWithValue("@DatabaseId", id); c.Parameters.AddWithValue("@Days", days); }, r => new CapacityHistoryPoint(Utc(r, "CollectedAtUtc"), Dec(r, "DataSizeMb"), Dec(r, "LogSizeMb"), Dec(r, "TotalSizeMb")), token);

    private async Task<SqlConnection> OpenAsync(CancellationToken token) { var c = new SqlConnection(_connectionString); await c.OpenAsync(token); return c; }
    private static SqlCommand Procedure(SqlConnection c, string name) => new(name, c) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 };
    private async Task<T?> OneAsync<T>(string name, Action<SqlCommand>? add, Func<SqlDataReader, T> map, CancellationToken token) where T : class { await using var c = await OpenAsync(token); await using var cmd = Procedure(c, name); add?.Invoke(cmd); await using var r = await cmd.ExecuteReaderAsync(token); return await r.ReadAsync(token) ? map(r) : null; }
    private async Task<IReadOnlyList<T>> ManyAsync<T>(string name, Action<SqlCommand>? add, Func<SqlDataReader, T> map, CancellationToken token) { await using var c = await OpenAsync(token); await using var cmd = Procedure(c, name); add?.Invoke(cmd); await using var r = await cmd.ExecuteReaderAsync(token); var rows = new List<T>(); while (await r.ReadAsync(token)) rows.Add(map(r)); return rows; }
    private static int I(SqlDataReader r, string n) => r.IsDBNull(r.GetOrdinal(n)) ? 0 : Convert.ToInt32(r[n]);
    private static long Long(SqlDataReader r, string n) => Convert.ToInt64(r[n]);
    private static long? LongNullable(SqlDataReader r, string n) => r.IsDBNull(r.GetOrdinal(n)) ? null : Convert.ToInt64(r[n]);
    private static decimal Dec(SqlDataReader r, string n) => r.IsDBNull(r.GetOrdinal(n)) ? 0 : Convert.ToDecimal(r[n]);
    private static decimal? DecNullable(SqlDataReader r, string n) => r.IsDBNull(r.GetOrdinal(n)) ? null : Convert.ToDecimal(r[n]);
    private static string S(SqlDataReader r, string n) => r.IsDBNull(r.GetOrdinal(n)) ? string.Empty : Convert.ToString(r[n]) ?? string.Empty;
    private static string? SNullable(SqlDataReader r, string n) => r.IsDBNull(r.GetOrdinal(n)) ? null : Convert.ToString(r[n]);
    private static DateTime? Date(SqlDataReader r, string n) => r.IsDBNull(r.GetOrdinal(n)) ? null : DateTime.SpecifyKind(Convert.ToDateTime(r[n]), DateTimeKind.Unspecified);
    private static DateTimeOffset Utc(SqlDataReader r, string n) => new(DateTime.SpecifyKind(Convert.ToDateTime(r[n]), DateTimeKind.Utc));
    private static DateTimeOffset? UtcNullable(SqlDataReader r, string n) => r.IsDBNull(r.GetOrdinal(n)) ? null : Utc(r, n);
}
