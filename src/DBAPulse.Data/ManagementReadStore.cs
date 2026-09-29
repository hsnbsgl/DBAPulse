using System.Data;
using Microsoft.Data.SqlClient;
using DBAPulse.Domain;

namespace DBAPulse.Data;

public sealed class ManagementReadStore
{
    private readonly string _connectionString;
    public ManagementReadStore(string connectionString) => _connectionString = new SqlConnectionStringBuilder(connectionString) { InitialCatalog = "DBA_PULSE" }.ConnectionString;
    public Task<ManagementOverview> OverviewAsync(CancellationToken t) => One("dbo.usp_Management_Overview", c => { }, r => new ManagementOverview(I(r,"ServerCount"),I(r,"DatabaseCount"),I(r,"CriticalEntityCount"),I(r,"WarningEntityCount"),I(r,"AttentionEntityCount"),I(r,"UnknownEntityCount"),I(r,"ActiveOperationalEvents"),I(r,"ActiveAnomalies"),I(r,"RelatedSignalGroups"),I(r,"NewCritical24h"),I(r,"Resolved24h"),Summary(r)), t);
    public async Task<PagedResult<ManagementAttentionRow>> AttentionAsync(string? severity,int? serverId,int? databaseId,string? domain,int page,int pageSize,CancellationToken t)
    {
        await using var r=await Execute("dbo.usp_Management_NeedsAttention",c=>{ Add(c,"@Severity",severity);Add(c,"@ServerId",serverId);Add(c,"@DatabaseId",databaseId);Add(c,"@Domain",domain);c.Parameters.AddWithValue("@Page",page);c.Parameters.AddWithValue("@PageSize",pageSize);},t);
        var items=new List<ManagementAttentionRow>(); while(await r.ReadAsync(t)) items.Add(new(Long(r,"Id"),S(r,"Severity"),S(r,"EntityType"),I(r,"ServerId"),NI(r,"DatabaseId"),S(r,"ServerName"),N(r,"DatabaseName"),S(r,"Domain"),S(r,"Issue"),S(r,"ExplanationCode"),Utc(r,"StartedAtUtc"),Utc(r,"LastSeenAtUtc"),I(r,"RelatedSignalCount"),S(r,"Status"),NL(r,"SourceEntityId")));
        var total=await r.NextResultAsync(t)&&await r.ReadAsync(t)?I(r,"TotalCount"):0; return new(items,page,pageSize,total);
    }
    public async Task<IReadOnlyList<ManagementHealthRow>> HealthAsync(int? serverId,int? databaseId,CancellationToken t)
    {
        await using var r=await Execute("dbo.usp_Management_Health",c=>{Add(c,"@ServerId",serverId);Add(c,"@DatabaseId",databaseId);},t); var list=new List<ManagementHealthRow>();
        while(await r.ReadAsync(t)) list.Add(new(S(r,"EntityType"),I(r,"ServerId"),NI(r,"DatabaseId"),S(r,"ServerName"),N(r,"DatabaseName"),S(r,"OverallStatus"),S(r,"PerformanceStatus"),S(r,"ProtectionStatus"),S(r,"AvailabilityStatus"),S(r,"CapacityStatus"),S(r,"AnomalyStatus"),S(r,"FreshnessStatus"),I(r,"ActiveCriticalCount"),I(r,"ActiveWarningCount"),I(r,"ActiveAttentionCount"),I(r,"RelatedSignalCount"))); return list;
    }
    public async Task<string> ServerEnvironmentAsync(int serverId, CancellationToken t)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(t);
        await using var command = new SqlCommand("SELECT COALESCE(NULLIF(Environment,N''),N'Dev') FROM dbo.Servers WHERE Id=@ServerId", connection);
        command.Parameters.AddWithValue("@ServerId", serverId);
        var value = await command.ExecuteScalarAsync(t);
        return Convert.ToString(value) ?? "Dev";
    }
    private async Task<SqlDataReader> Execute(string name,Action<SqlCommand> add,CancellationToken t){var c=new SqlConnection(_connectionString);await c.OpenAsync(t);var cmd=new SqlCommand(name,c){CommandType=CommandType.StoredProcedure,CommandTimeout=60};add(cmd);return await cmd.ExecuteReaderAsync(CommandBehavior.CloseConnection,t);}
    private async Task<T> One<T>(string name,Action<SqlCommand> add,Func<SqlDataReader,T> map,CancellationToken t){await using var r=await Execute(name,add,t);return await r.ReadAsync(t)?map(r):throw new InvalidOperationException("Management procedure returned no row.");}
    private static void Add(SqlCommand c,string n,object? v)=>c.Parameters.AddWithValue(n,v??DBNull.Value);
    private static int I(SqlDataReader r,string n)=>Convert.ToInt32(r[n]); private static long Long(SqlDataReader r,string n)=>Convert.ToInt64(r[n]); private static long? NL(SqlDataReader r,string n)=>r[n] is DBNull?null:Convert.ToInt64(r[n]); private static int? NI(SqlDataReader r,string n)=>r[n] is DBNull?null:Convert.ToInt32(r[n]); private static string S(SqlDataReader r,string n)=>Convert.ToString(r[n])??string.Empty; private static string? N(SqlDataReader r,string n)=>r[n] is DBNull?null:Convert.ToString(r[n]); private static DateTimeOffset Utc(SqlDataReader r,string n)=>new(DateTime.SpecifyKind(Convert.ToDateTime(r[n]),DateTimeKind.Utc)); private static string Summary(SqlDataReader r)=>$"{I(r,"CriticalEntityCount")} critical and {I(r,"WarningEntityCount")} warning conditions require attention.";
}
