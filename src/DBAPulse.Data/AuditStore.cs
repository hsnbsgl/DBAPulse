using System.Data;
using DBAPulse.Domain;
using Microsoft.Data.SqlClient;

namespace DBAPulse.Data;

public sealed class AuditStore
{
    private readonly string _connectionString;
    public AuditStore(string connectionString) => _connectionString = new SqlConnectionStringBuilder(connectionString) { InitialCatalog = "DBA_PULSE" }.ConnectionString;

    public async Task InsertAsync(AuditLogEntry entry, CancellationToken token)
    {
        await using var connection = await OpenAsync(token);
        await using var command = Procedure(connection, "dbo.usp_AuditLog_Insert");
        command.Parameters.Add(new SqlParameter("@OccurredAtUtc", SqlDbType.DateTime2) { Value = entry.OccurredAtUtc.UtcDateTime });
        command.Parameters.AddWithValue("@UserName", entry.UserName);
        command.Parameters.AddWithValue("@Action", entry.Action);
        command.Parameters.AddWithValue("@ResourceType", entry.ResourceType);
        command.Parameters.AddWithValue("@HttpMethod", entry.HttpMethod);
        command.Parameters.AddWithValue("@RequestPath", entry.RequestPath);
        command.Parameters.AddWithValue("@Result", entry.Result);
        command.Parameters.AddWithValue("@StatusCode", entry.StatusCode);
        command.Parameters.AddWithValue("@DurationMs", entry.DurationMs);
        command.Parameters.AddWithValue("@CorrelationId", entry.CorrelationId);
        command.Parameters.AddWithValue("@UserRole", (object?)entry.UserRole ?? DBNull.Value);
        command.Parameters.AddWithValue("@ResourceId", (object?)entry.ResourceId ?? DBNull.Value);
        command.Parameters.AddWithValue("@ClientIp", (object?)entry.ClientIp ?? DBNull.Value);
        command.Parameters.AddWithValue("@UserAgent", (object?)entry.UserAgent ?? DBNull.Value);
        command.Parameters.AddWithValue("@AdditionalData", (object?)entry.AdditionalData ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(token);
    }

    public async Task<PagedResult<AuditLogEntry>> ListAsync(DateTimeOffset? fromUtc, DateTimeOffset? toUtc, string? userName, string? action, string? resourceType, string? result, string? correlationId, int page, int pageSize, CancellationToken token)
    {
        await using var connection = await OpenAsync(token);
        await using var command = Procedure(connection, "dbo.usp_AuditLogs_List");
        command.Parameters.Add(new SqlParameter("@FromUtc", SqlDbType.DateTime2) { Value = (object?)fromUtc?.UtcDateTime ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@ToUtc", SqlDbType.DateTime2) { Value = (object?)toUtc?.UtcDateTime ?? DBNull.Value });
        command.Parameters.AddWithValue("@UserName", (object?)Limit(userName, 256) ?? DBNull.Value);
        command.Parameters.AddWithValue("@Action", (object?)Limit(action, 128) ?? DBNull.Value);
        command.Parameters.AddWithValue("@ResourceType", (object?)Limit(resourceType, 64) ?? DBNull.Value);
        command.Parameters.AddWithValue("@Result", (object?)Limit(result, 16) ?? DBNull.Value);
        command.Parameters.AddWithValue("@CorrelationId", (object?)Limit(correlationId, 64) ?? DBNull.Value);
        command.Parameters.AddWithValue("@Page", page); command.Parameters.AddWithValue("@PageSize", pageSize);
        await using var reader = await command.ExecuteReaderAsync(token);
        var items = new List<AuditLogEntry>();
        while (await reader.ReadAsync(token)) items.Add(Read(reader));
        var total = 0;
        if (await reader.NextResultAsync(token) && await reader.ReadAsync(token)) total = Convert.ToInt32(reader["TotalCount"]);
        return new(items, page, pageSize, total);
    }

    private static AuditLogEntry Read(SqlDataReader r) => new(Convert.ToInt64(r["Id"]), Utc(r, "OccurredAtUtc"), S(r, "UserName"), N(r, "UserRole"), S(r, "Action"), S(r, "ResourceType"), N(r, "ResourceId"), S(r, "HttpMethod"), S(r, "RequestPath"), S(r, "Result"), Convert.ToInt32(r["StatusCode"]), Convert.ToInt64(r["DurationMs"]), S(r, "CorrelationId"), N(r, "ClientIp"), N(r, "UserAgent"), N(r, "AdditionalData"));
    private async Task<SqlConnection> OpenAsync(CancellationToken token) { var c = new SqlConnection(_connectionString); await c.OpenAsync(token); return c; }
    private static SqlCommand Procedure(SqlConnection c, string name) => new(name, c) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 };
    private static string? Limit(string? value, int max) => string.IsNullOrWhiteSpace(value) ? null : value[..Math.Min(value.Length, max)];
    private static string S(SqlDataReader r, string name) => Convert.ToString(r[name]) ?? string.Empty;
    private static string? N(SqlDataReader r, string name) => r.IsDBNull(r.GetOrdinal(name)) ? null : Convert.ToString(r[name]);
    private static DateTimeOffset Utc(SqlDataReader r, string name) => new(DateTime.SpecifyKind(Convert.ToDateTime(r[name]), DateTimeKind.Utc));
}
