using System.Data;
using DBAPulse.Domain;
using Microsoft.Data.SqlClient;

namespace DBAPulse.Data;

public sealed class PerformanceStore
{
    private readonly string _connectionString;
    public PerformanceStore(string connectionString) => _connectionString = new SqlConnectionStringBuilder(connectionString) { InitialCatalog = "DBA_PULSE" }.ConnectionString;

    public async Task<PerformanceOverview> GetOverviewAsync(int hours, CancellationToken token)
    {
        await using var reader = await ExecuteAsync("dbo.usp_Performance_Overview", hours, token);
        await reader.ReadAsync(token);
        return new(Convert.ToInt64(reader["BlockingObservationCount"]), Convert.ToInt64(reader["MaxBlockingDurationMs"]), Convert.ToInt64(reader["DeadlockCount"]), Convert.ToInt64(reader["LongRunningObservationCount"]), UtcNullable(reader, "LastPerformanceCollectionAtUtc"));
    }

    public Task<IReadOnlyList<BlockingRow>> GetBlockingAsync(int hours, CancellationToken token) => ReadAsync("dbo.usp_Blocking_Recent", hours, r => new BlockingRow(Convert.ToInt64(r["Id"]), Utc(r, "CapturedAtUtc"), S(r, "ServerName"), N(r, "DatabaseName"), Convert.ToInt32(r["SessionId"]), Convert.ToInt32(r["BlockingSessionId"]), N(r, "WaitType"), Convert.ToInt64(r["WaitDurationMs"]), N(r, "Command"), N(r, "HostName"), N(r, "ApplicationName"), N(r, "LoginName"), N(r, "SqlTextHash"), N(r, "SqlTextPreview")), token);
    public Task<IReadOnlyList<DeadlockRow>> GetDeadlocksAsync(int hours, CancellationToken token) => ReadAsync("dbo.usp_Deadlocks_Recent", hours, r => new DeadlockRow(Convert.ToInt64(r["Id"]), Utc(r, "OccurredAtUtc"), Utc(r, "CollectedAtUtc"), S(r, "ServerName"), N(r, "DatabaseName"), N(r, "VictimProcessId"), IntNullable(r, "VictimSessionId"), Convert.ToInt32(r["ProcessCount"]), S(r, "DeadlockHash")), token);
    public Task<IReadOnlyList<LongRunningRow>> GetLongRunningAsync(int hours, CancellationToken token) => ReadAsync("dbo.usp_LongRunning_Recent", hours, r => new LongRunningRow(Convert.ToInt64(r["Id"]), Utc(r, "CapturedAtUtc"), S(r, "ServerName"), N(r, "DatabaseName"), Convert.ToInt32(r["SessionId"]), Convert.ToInt64(r["ElapsedMs"]), N(r, "Status"), N(r, "Command"), N(r, "WaitType"), LongNullable(r, "WaitTimeMs"), LongNullable(r, "CpuTimeMs"), LongNullable(r, "LogicalReads"), LongNullable(r, "Reads"), LongNullable(r, "Writes"), N(r, "HostName"), N(r, "ApplicationName"), N(r, "LoginName"), N(r, "SqlTextHash"), N(r, "SqlTextPreview")), token);
    public Task<IReadOnlyList<WaitStatsRow>> GetWaitsAsync(int hours, CancellationToken token) => ReadAsync("dbo.usp_WaitStats_Top", hours, r => new WaitStatsRow(S(r, "WaitType"), Convert.ToInt64(r["WaitTimeDeltaMs"]), Convert.ToInt64(r["SignalWaitDeltaMs"]), Convert.ToInt64(r["WaitingTasksDelta"]), Convert.ToDecimal(r["Percentage"])), token);

    private async Task<SqlDataReader> ExecuteAsync(string procedure, int hours, CancellationToken token)
    {
        var connection = new SqlConnection(_connectionString); await connection.OpenAsync(token);
        var command = new SqlCommand(procedure, connection) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 };
        command.Parameters.AddWithValue("@Hours", AllowedHours(hours));
        return await command.ExecuteReaderAsync(CommandBehavior.CloseConnection, token);
    }
    private async Task<IReadOnlyList<T>> ReadAsync<T>(string procedure, int hours, Func<SqlDataReader, T> mapper, CancellationToken token)
    {
        await using var reader = await ExecuteAsync(procedure, hours, token); var result = new List<T>();
        while (await reader.ReadAsync(token)) result.Add(mapper(reader));
        return result;
    }
    public static int AllowedHours(int value) => value is 1 or 6 or 12 or 24 or 48 or 168 ? value : 24;
    private static string S(SqlDataReader r, string name) => Convert.ToString(r[name]) ?? string.Empty;
    private static string? N(SqlDataReader r, string name) => r.IsDBNull(r.GetOrdinal(name)) ? null : Convert.ToString(r[name]);
    private static long? LongNullable(SqlDataReader r, string name) => r.IsDBNull(r.GetOrdinal(name)) ? null : Convert.ToInt64(r[name]);
    private static int? IntNullable(SqlDataReader r, string name) => r.IsDBNull(r.GetOrdinal(name)) ? null : Convert.ToInt32(r[name]);
    private static DateTimeOffset Utc(SqlDataReader r, string name) => new(DateTime.SpecifyKind(Convert.ToDateTime(r[name]), DateTimeKind.Utc));
    private static DateTimeOffset? UtcNullable(SqlDataReader r, string name) => r.IsDBNull(r.GetOrdinal(name)) ? null : Utc(r, name);
}
