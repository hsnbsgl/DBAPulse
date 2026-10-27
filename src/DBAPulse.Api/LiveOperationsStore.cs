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
public sealed record ObjectExplorerItem(string SchemaName, string ObjectName);
public sealed record ObjectExplorerSnapshot(IReadOnlyList<ObjectExplorerItem> Tables, IReadOnlyList<ObjectExplorerItem> Procedures, IReadOnlyList<ObjectExplorerItem> Views, IReadOnlyList<ObjectExplorerItem> Functions);
public sealed record ObjectDefinition(string SchemaName, string ObjectName, string ObjectType, string Definition);
public sealed record ObjectDefinitionRequest(int ServerId, string DatabaseName, string SchemaName, string ObjectName, string ObjectType);

public sealed class LiveOperationsStore
{
    private const string InstallWhoIsActiveSql = """
        IF OBJECT_ID(N'dbo.sp_WhoIsActive', N'P') IS NULL
        BEGIN
            EXEC(N'
        CREATE PROCEDURE dbo.sp_WhoIsActive
        AS
        BEGIN
            SET NOCOUNT ON;
            SELECT TOP (100)
                s.session_id,
                r.status,
                DB_NAME(COALESCE(r.database_id, s.database_id)) AS database_name,
                CONVERT(nvarchar(4000), st.text) AS sql_text,
                r.wait_type,
                r.wait_time,
                NULLIF(r.blocking_session_id, 0) AS blocking_session_id,
                s.login_name,
                s.host_name,
                s.program_name,
                COALESCE(r.start_time, s.last_request_start_time) AS start_time,
                SYSUTCDATETIME() AS collection_time,
                COALESCE(r.cpu_time, 0) AS CPU,
                COALESCE(r.reads, 0) AS reads,
                COALESCE(r.writes, 0) AS writes,
                s.open_transaction_count AS open_tran_count
            FROM sys.dm_exec_sessions AS s
            LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
            OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
            WHERE s.is_user_process = 1 AND s.session_id <> @@SPID
            ORDER BY COALESCE(r.total_elapsed_time, 0) DESC, s.session_id;
        END');
        END;
        """;

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

    public async Task<IReadOnlyList<IReadOnlyDictionary<string, object?>>> GetWhoIsActiveAsync(int serverId, CancellationToken token)
    {
        var sourceConnection = await ResolveSourceConnectionAsync(serverId, token);
        if (sourceConnection is null)
            throw new InvalidOperationException($"No live source connection is configured for server {serverId}.");

        var masterConnection = new SqlConnectionStringBuilder(sourceConnection) { InitialCatalog = "master" }.ConnectionString;
        await using var connection = new SqlConnection(masterConnection);
        await connection.OpenAsync(token);
        await using (var installCommand = new SqlCommand(InstallWhoIsActiveSql, connection) { CommandTimeout = 10 })
            await installCommand.ExecuteNonQueryAsync(token);
        await using var command = new SqlCommand("EXEC master.dbo.sp_WhoIsActive;", connection) { CommandTimeout = 10 };
        await using var reader = await command.ExecuteReaderAsync(token);
        var rows = new List<IReadOnlyDictionary<string, object?>>();
        while (await reader.ReadAsync(token) && rows.Count < 100)
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (var index = 0; index < reader.FieldCount; index++)
                row[reader.GetName(index)] = NormalizeWhoIsActiveValue(reader.GetValue(index));
            rows.Add(row);
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

    public async Task<ObjectExplorerSnapshot> GetObjectExplorerAsync(int serverId, string databaseName, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(databaseName) || databaseName.Length > 128)
            throw new ArgumentException("A valid database name is required.", nameof(databaseName));

        var sourceConnection = await ResolveSourceConnectionAsync(serverId, token);
        if (sourceConnection is null)
            throw new InvalidOperationException($"No live source connection is configured for server {serverId}.");

        const string sql = """
            SELECT
                CASE
                    WHEN o.type = 'U' THEN N'Table'
                    WHEN o.type IN ('P', 'PC') THEN N'Procedure'
                    WHEN o.type = 'V' THEN N'View'
                    WHEN o.type IN ('FN', 'IF', 'TF', 'FS', 'FT') THEN N'Function'
                END AS object_type,
                s.name AS schema_name,
                o.name AS object_name
            FROM {0}.sys.objects AS o
            INNER JOIN {0}.sys.schemas AS s ON s.schema_id = o.schema_id
            WHERE o.is_ms_shipped = 0
              AND o.type IN ('U', 'P', 'PC', 'V', 'FN', 'IF', 'TF', 'FS', 'FT');
            """;

        var masterConnection = new SqlConnectionStringBuilder(sourceConnection) { InitialCatalog = "master" }.ConnectionString;
        await using var connection = new SqlConnection(masterConnection);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand(string.Format(sql, QuoteIdentifier(databaseName)), connection) { CommandTimeout = 15 };
        await using var reader = await command.ExecuteReaderAsync(token);
        var tables = new List<ObjectExplorerItem>();
        var procedures = new List<ObjectExplorerItem>();
        var views = new List<ObjectExplorerItem>();
        var functions = new List<ObjectExplorerItem>();
        while (await reader.ReadAsync(token))
        {
            var item = new ObjectExplorerItem(String(reader, "schema_name"), String(reader, "object_name"));
            switch (String(reader, "object_type"))
            {
                case "Table": tables.Add(item); break;
                case "Procedure": procedures.Add(item); break;
                case "View": views.Add(item); break;
                case "Function": functions.Add(item); break;
            }
        }

        return new(
            tables.OrderBy(item => (item.SchemaName, item.ObjectName), StringTupleComparer.Instance).ToList(),
            procedures.OrderBy(item => (item.SchemaName, item.ObjectName), StringTupleComparer.Instance).ToList(),
            views.OrderBy(item => (item.SchemaName, item.ObjectName), StringTupleComparer.Instance).ToList(),
            functions.OrderBy(item => (item.SchemaName, item.ObjectName), StringTupleComparer.Instance).ToList());
    }

    public async Task<ObjectDefinition?> GetObjectDefinitionAsync(int serverId, string databaseName, string schemaName, string objectName, string objectType, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(databaseName) || string.IsNullOrWhiteSpace(schemaName) || string.IsNullOrWhiteSpace(objectName))
            throw new ArgumentException("Database, schema and object names are required.");
        if (!new[] { "Table", "Procedure", "View", "Function" }.Contains(objectType, StringComparer.OrdinalIgnoreCase))
            throw new ArgumentException("Unsupported object type.", nameof(objectType));

        var sourceConnection = await ResolveSourceConnectionAsync(serverId, token);
        if (sourceConnection is null)
            throw new InvalidOperationException($"No live source connection is configured for server {serverId}.");
        var databaseConnection = new SqlConnectionStringBuilder(sourceConnection) { InitialCatalog = databaseName }.ConnectionString;

        await using var connection = new SqlConnection(databaseConnection);
        await connection.OpenAsync(token);
        if (string.Equals(objectType, "Table", StringComparison.OrdinalIgnoreCase))
        {
            const string tableSql = """
                SELECT c.name AS column_name, TYPE_NAME(c.user_type_id) AS type_name, c.max_length,
                       c.precision, c.scale, c.is_nullable, c.is_identity
                FROM sys.tables AS t
                INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
                INNER JOIN sys.columns AS c ON c.object_id = t.object_id
                WHERE s.name = @SchemaName AND t.name = @ObjectName AND t.is_ms_shipped = 0
                ORDER BY c.column_id;
                """;
            await using var tableCommand = new SqlCommand(tableSql, connection) { CommandTimeout = 15 };
            tableCommand.Parameters.AddWithValue("@SchemaName", schemaName);
            tableCommand.Parameters.AddWithValue("@ObjectName", objectName);
            await using var tableReader = await tableCommand.ExecuteReaderAsync(token);
            var columns = new List<string>();
            while (await tableReader.ReadAsync(token))
            {
                var typeName = Convert.ToString(tableReader["type_name"]) ?? "sql_variant";
                var maxLength = Convert.ToInt32(tableReader["max_length"]);
                var precision = Convert.ToInt32(tableReader["precision"]);
                var scale = Convert.ToInt32(tableReader["scale"]);
                var type = typeName.ToLowerInvariant() switch
                {
                    "nvarchar" or "nchar" => $"{typeName}({(maxLength < 0 ? "max" : (maxLength / 2).ToString())})",
                    "varchar" or "char" or "varbinary" or "binary" => $"{typeName}({(maxLength < 0 ? "max" : maxLength.ToString())})",
                    "decimal" or "numeric" => $"{typeName}({precision},{scale})",
                    "datetime2" or "datetimeoffset" or "time" => $"{typeName}({scale})",
                    _ => typeName,
                };
                var nullable = Convert.ToBoolean(tableReader["is_nullable"]) ? "NULL" : "NOT NULL";
                var identity = Convert.ToBoolean(tableReader["is_identity"]) ? " IDENTITY(1,1)" : string.Empty;
                columns.Add($"    {QuoteIdentifier(Convert.ToString(tableReader["column_name"]) ?? string.Empty)} {type}{identity} {nullable}");
            }
            return columns.Count == 0 ? null : new(schemaName, objectName, "Table", $"CREATE TABLE {QuoteIdentifier(schemaName)}.{QuoteIdentifier(objectName)} (\n{string.Join(",\n", columns)}\n);");
        }

        const string moduleSql = """
            SELECT sm.definition
            FROM sys.sql_modules AS sm
            INNER JOIN sys.objects AS o ON o.object_id = sm.object_id
            INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
            WHERE s.name = @SchemaName AND o.name = @ObjectName AND o.is_ms_shipped = 0
              AND ((@ObjectType = N'Procedure' AND o.type IN ('P', 'PC'))
                OR (@ObjectType = N'View' AND o.type = 'V')
                OR (@ObjectType = N'Function' AND o.type IN ('FN', 'IF', 'TF', 'FS', 'FT')));
            """;
        await using var moduleCommand = new SqlCommand(moduleSql, connection) { CommandTimeout = 15 };
        moduleCommand.Parameters.AddWithValue("@SchemaName", schemaName);
        moduleCommand.Parameters.AddWithValue("@ObjectName", objectName);
        moduleCommand.Parameters.AddWithValue("@ObjectType", objectType);
        var definition = Convert.ToString(await moduleCommand.ExecuteScalarAsync(token));
        return string.IsNullOrWhiteSpace(definition) ? null : new(schemaName, objectName, objectType, definition);
    }

    private static string QuoteIdentifier(string value) => $"[{value.Replace("]", "]]", StringComparison.Ordinal)}]";

    private sealed class StringTupleComparer : IComparer<(string SchemaName, string ObjectName)>
    {
        public static readonly StringTupleComparer Instance = new();
        public int Compare((string SchemaName, string ObjectName) left, (string SchemaName, string ObjectName) right)
        {
            var schema = StringComparer.OrdinalIgnoreCase.Compare(left.SchemaName, right.SchemaName);
            return schema != 0 ? schema : StringComparer.OrdinalIgnoreCase.Compare(left.ObjectName, right.ObjectName);
        }
    }

    private async Task<string?> ResolveSourceConnectionAsync(int serverId, CancellationToken token)
    {
        if (_serverConnections.TryGetValue(serverId, out var configured)) return configured;

        await using var connection = new SqlConnection(_managementConnection);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand("SELECT COUNT(*) FROM dbo.Servers WHERE IsActive = 1", connection);
        var activeServerCount = Convert.ToInt32(await command.ExecuteScalarAsync(token));

        // The default source connection is sufficient for a single-server
        // installation even when that server's identity is not 1 (for
        // example, after old server records were removed). Multi-server
        // installations must provide DBAPULSE_LIVE_SOURCE_CONNECTIONS so a
        // live query cannot accidentally run against the wrong instance.
        return activeServerCount == 1 ? _connectionString : null;
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

    private static object? NormalizeWhoIsActiveValue(object value) => value switch
    {
        DBNull => null,
        byte[] bytes => Convert.ToBase64String(bytes),
        DateTime dateTime => DateTime.SpecifyKind(dateTime, DateTimeKind.Utc),
        DateTimeOffset dateTimeOffset => dateTimeOffset,
        _ => value,
    };
}
