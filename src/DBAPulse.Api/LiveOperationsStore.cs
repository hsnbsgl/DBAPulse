using Microsoft.Data.SqlClient;
using System.Text.Json;

namespace DBAPulse.Api;

public sealed record LiveRequestRow(
    int SessionId,
    int? BlockingSessionId,
    string? DatabaseName,
    string Status,
    string Command,
    int CpuTimeMs,
    long ElapsedMs,
    string? WaitType,
    int WaitTimeMs,
    string? LoginName,
    string? HostName,
    string? ApplicationName,
    DateTimeOffset StartTimeUtc,
    string? SqlText);

public sealed record LiveConnectionApplicationRow(string ApplicationName, int ConnectionCount);
public sealed record LiveConnectionsSnapshot(int ActiveConnectionCount, int DistinctApplicationCount, IReadOnlyList<LiveConnectionApplicationRow> Applications);

public sealed class LiveOperationsStore
{
    private readonly string _connectionString;
    private readonly string _managementConnection;
    private readonly Dictionary<int, string> _serverConnections;

    public LiveOperationsStore(string managementConnection, string defaultSourceConnection, string? serverConnections)
    {
        _managementConnection = managementConnection;
        _connectionString = defaultSourceConnection;
        _serverConnections = ParseConnections(serverConnections);
    }

    public async Task<IReadOnlyList<LiveRequestRow>> GetRequestsAsync(int serverId, CancellationToken token)
    {
        const string sql = """
            SELECT TOP (100)
                r.session_id,
                NULLIF(r.blocking_session_id, 0) AS blocking_session_id,
                DB_NAME(r.database_id) AS database_name,
                r.status,
                r.command,
                r.cpu_time,
                r.total_elapsed_time,
                r.wait_type,
                r.wait_time,
                s.login_name,
                s.host_name,
                s.program_name,
                r.start_time,
                CONVERT(nvarchar(4000), st.text) AS sql_text
            FROM sys.dm_exec_requests AS r
            LEFT JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
            OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
            WHERE r.session_id <> @@SPID
            ORDER BY r.total_elapsed_time DESC;
            """;

        var sourceConnection = await ResolveSourceConnectionAsync(serverId, token);
        if (sourceConnection is null)
            throw new InvalidOperationException($"No live source connection is configured for server {serverId}.");

        await using var connection = new SqlConnection(sourceConnection);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand(sql, connection) { CommandTimeout = 10 };
        await using var reader = await command.ExecuteReaderAsync(token);
        var rows = new List<LiveRequestRow>();
        while (await reader.ReadAsync(token))
        {
            rows.Add(new(
                Convert.ToInt32(reader["session_id"]),
                NullableInt(reader, "blocking_session_id"),
                NullableString(reader, "database_name"),
                String(reader, "status"),
                String(reader, "command"),
                Convert.ToInt32(reader["cpu_time"]),
                Convert.ToInt64(reader["total_elapsed_time"]),
                NullableString(reader, "wait_type"),
                Convert.ToInt32(reader["wait_time"]),
                NullableString(reader, "login_name"),
                NullableString(reader, "host_name"),
                NullableString(reader, "program_name"),
                new DateTimeOffset(DateTime.SpecifyKind(reader.GetDateTime(reader.GetOrdinal("start_time")), DateTimeKind.Utc)),
                NullableString(reader, "sql_text")));
        }

        return rows;
    }

    public async Task<LiveConnectionsSnapshot> GetConnectionsAsync(int serverId, CancellationToken token)
    {
        const string sql = """
            SELECT
                COALESCE(NULLIF(LTRIM(RTRIM(program_name)), N''), N'(unknown)') AS application_name,
                COUNT(*) AS connection_count
            FROM sys.dm_exec_sessions
            WHERE is_user_process = 1 AND session_id <> @@SPID
            GROUP BY COALESCE(NULLIF(LTRIM(RTRIM(program_name)), N''), N'(unknown)')
            ORDER BY COUNT(*) DESC, application_name;
            """;

        var sourceConnection = await ResolveSourceConnectionAsync(serverId, token);
        if (sourceConnection is null)
            throw new InvalidOperationException($"No live source connection is configured for server {serverId}.");

        await using var connection = new SqlConnection(sourceConnection);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand(sql, connection) { CommandTimeout = 10 };
        await using var reader = await command.ExecuteReaderAsync(token);
        var applications = new List<LiveConnectionApplicationRow>();
        while (await reader.ReadAsync(token))
            applications.Add(new(String(reader, "application_name"), Convert.ToInt32(reader["connection_count"])));

        return new(applications.Sum(row => row.ConnectionCount), applications.Count, applications);
    }

    private async Task<string?> ResolveSourceConnectionAsync(int serverId, CancellationToken token)
    {
        if (_serverConnections.TryGetValue(serverId, out var configured)) return configured;

        await using var connection = new SqlConnection(_managementConnection);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand("SELECT TOP (1) Id FROM dbo.Servers ORDER BY Id", connection);
        var primaryServerId = Convert.ToInt32(await command.ExecuteScalarAsync(token));
        return primaryServerId == serverId ? _connectionString : null;
    }

    private static Dictionary<int, string> ParseConnections(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return new();
        try
        {
            return JsonSerializer.Deserialize<Dictionary<int, string>>(value) ?? new();
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException("DBAPULSE_LIVE_SOURCE_CONNECTIONS must be a JSON object keyed by serverId.", exception);
        }
    }

    private static string String(SqlDataReader reader, string name) => Convert.ToString(reader[name]) ?? string.Empty;
    private static string? NullableString(SqlDataReader reader, string name) => reader.IsDBNull(reader.GetOrdinal(name)) ? null : Convert.ToString(reader[name]);
    private static int? NullableInt(SqlDataReader reader, string name) => reader.IsDBNull(reader.GetOrdinal(name)) ? null : Convert.ToInt32(reader[name]);
}
