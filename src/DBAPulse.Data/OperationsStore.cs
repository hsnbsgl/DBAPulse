using System.Data;
using DBAPulse.Domain;
using Microsoft.Data.SqlClient;

namespace DBAPulse.Data;

public sealed class OperationsStore
{
    private readonly string _connectionString;
    public OperationsStore(string connectionString) => _connectionString = new SqlConnectionStringBuilder(connectionString) { InitialCatalog = "DBA_PULSE" }.ConnectionString;
    public async Task<OperationsOverview> GetOverviewAsync(int hours, CancellationToken token)
    {
        await using var reader = await ExecuteAsync("dbo.usp_OperationalEvents_Overview", c => c.Parameters.AddWithValue("@Hours", AllowedHours(hours)), token);
        await reader.ReadAsync(token);
        return new(Convert.ToInt32(reader["ActiveEventCount"]), Convert.ToInt32(reader["ActiveCriticalCount"]), Convert.ToInt32(reader["ActiveWarningCount"]), Convert.ToInt32(reader["ResolvedEventCount"]), Convert.ToInt32(reader["BlockingEventCount"]), Convert.ToInt32(reader["LongRunningEventCount"]), Convert.ToInt32(reader["DeadlockEventCount"]));
    }
    public async Task<PagedResult<OperationalEventRow>> ListAsync(DateTimeOffset? fromUtc, DateTimeOffset? toUtc, string? status, string? severity, string? eventType, int? serverId, int? databaseId, int page, int pageSize, CancellationToken token)
    {
        await using var reader = await ExecuteAsync("dbo.usp_OperationalEvents_List", c => { AddDate(c, "@FromUtc", fromUtc); AddDate(c, "@ToUtc", toUtc); c.Parameters.AddWithValue("@Status", (object?)Limit(status, 20) ?? DBNull.Value); c.Parameters.AddWithValue("@Severity", (object?)Limit(severity, 20) ?? DBNull.Value); c.Parameters.AddWithValue("@EventType", (object?)Limit(eventType, 40) ?? DBNull.Value); c.Parameters.AddWithValue("@ServerId", (object?)serverId ?? DBNull.Value); c.Parameters.AddWithValue("@DatabaseId", (object?)databaseId ?? DBNull.Value); c.Parameters.AddWithValue("@Page", page); c.Parameters.AddWithValue("@PageSize", Math.Clamp(pageSize, 1, 100)); }, token);
        var items = new List<OperationalEventRow>(); while (await reader.ReadAsync(token)) items.Add(ReadRow(reader)); var total = 0;
        if (await reader.NextResultAsync(token) && await reader.ReadAsync(token)) total = Convert.ToInt32(reader["TotalCount"]);
        return new(items, page, Math.Clamp(pageSize, 1, 100), total);
    }
    public async Task<OperationalEventDetail?> DetailAsync(long id, CancellationToken token)
    {
        await using var reader = await ExecuteAsync("dbo.usp_OperationalEvent_Detail", c => c.Parameters.AddWithValue("@Id", id), token);
        return await reader.ReadAsync(token) ? new(Convert.ToInt64(reader["Id"]), S(reader,"EventType"), S(reader,"ServerName"), N(reader,"DatabaseName"), S(reader,"Fingerprint"), Utc(reader,"StartedAtUtc"), Utc(reader,"LastSeenAtUtc"), UtcNullable(reader,"EndedAtUtc"), Convert.ToInt64(reader["DurationMs"]), S(reader,"Status"), S(reader,"Severity"), Convert.ToInt32(reader["ObservationCount"]), IntNullable(reader,"AffectedSessionCount"), S(reader,"Title"), S(reader,"Summary"), LongNullable(reader,"SourceEntityId"), Utc(reader,"CreatedAtUtc"), Utc(reader,"UpdatedAtUtc"), N(reader,"AdditionalData")) : null;
    }
    private async Task<SqlDataReader> ExecuteAsync(string procedure, Action<SqlCommand> configure, CancellationToken token) { var c = new SqlConnection(_connectionString); await c.OpenAsync(token); var cmd = new SqlCommand(procedure,c){CommandType=CommandType.StoredProcedure,CommandTimeout=60}; configure(cmd); return await cmd.ExecuteReaderAsync(CommandBehavior.CloseConnection, token); }
    private static OperationalEventRow ReadRow(SqlDataReader r) => new(Convert.ToInt64(r["Id"]),S(r,"EventType"),S(r,"ServerName"),N(r,"DatabaseName"),S(r,"Fingerprint"),Utc(r,"StartedAtUtc"),Utc(r,"LastSeenAtUtc"),UtcNullable(r,"EndedAtUtc"),Convert.ToInt64(r["DurationMs"]),S(r,"Status"),S(r,"Severity"),Convert.ToInt32(r["ObservationCount"]),IntNullable(r,"AffectedSessionCount"),S(r,"Title"),S(r,"Summary"));
    public static int AllowedHours(int value) => value is 1 or 6 or 12 or 24 or 48 or 168 ? value : 24;
    private static void AddDate(SqlCommand c,string name,DateTimeOffset? v)=>c.Parameters.Add(new SqlParameter(name,SqlDbType.DateTime2){Value=(object?)v?.UtcDateTime??DBNull.Value});
    private static string? Limit(string? v,int m)=>string.IsNullOrWhiteSpace(v)?null:v[..Math.Min(v.Length,m)]; private static string S(SqlDataReader r,string n)=>Convert.ToString(r[n])??string.Empty; private static string? N(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Convert.ToString(r[n]); private static int? IntNullable(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Convert.ToInt32(r[n]); private static long? LongNullable(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Convert.ToInt64(r[n]); private static DateTimeOffset Utc(SqlDataReader r,string n)=>new(DateTime.SpecifyKind(Convert.ToDateTime(r[n]),DateTimeKind.Utc)); private static DateTimeOffset? UtcNullable(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Utc(r,n);
}
