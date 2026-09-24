using System.Data;
using DBAPulse.Domain;
using Microsoft.Data.SqlClient;

namespace DBAPulse.Data;

public sealed class BaselineStore
{
    private readonly string _connectionString;
    public BaselineStore(string connectionString) => _connectionString = new SqlConnectionStringBuilder(connectionString) { InitialCatalog = "DBA_PULSE" }.ConnectionString;

    public async Task<IReadOnlyList<AnomalySample>> SamplesAsync(DateTime fromUtc, DateTime toUtc, CancellationToken token)
    {
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, "dbo.usp_AnomalySamples_List");
        command.Parameters.Add(new SqlParameter("@FromUtc", SqlDbType.DateTime2) { Value = fromUtc }); command.Parameters.Add(new SqlParameter("@ToUtc", SqlDbType.DateTime2) { Value = toUtc });
        await using var reader = await command.ExecuteReaderAsync(token); var result = new List<AnomalySample>();
        while (await reader.ReadAsync(token)) result.Add(new(S(reader, 0), Convert.ToInt32(reader.GetValue(1)), IntNullable(reader, 2), N(reader, 3), Utc(reader, 4), Convert.ToDecimal(reader.GetValue(5)), LongNullable(reader, 6)));
        return result;
    }

    public async Task ReplaceBaselinesAsync(IReadOnlyCollection<BaselineResult> rows, DateTime calculatedAtUtc, CancellationToken token)
    {
        var table = new DataTable();
        foreach (var c in new[] { ("MetricType", typeof(string)), ("ServerId", typeof(int)), ("DatabaseId", typeof(int)), ("EntityKey", typeof(string)), ("DayOfWeek", typeof(byte)), ("HourOfDay", typeof(byte)), ("WindowDays", typeof(int)), ("SampleCount", typeof(int)), ("MedianValue", typeof(decimal)), ("P75Value", typeof(decimal)), ("P90Value", typeof(decimal)), ("P95Value", typeof(decimal)), ("P99Value", typeof(decimal)), ("MeanValue", typeof(decimal)), ("StdDevValue", typeof(decimal)), ("MadValue", typeof(decimal)), ("MinValue", typeof(decimal)), ("MaxValue", typeof(decimal)), ("CalculatedAtUtc", typeof(DateTime)), ("ValidFromUtc", typeof(DateTime)), ("Status", typeof(string)), ("BaselineScope", typeof(string)) }) table.Columns.Add(c.Item1, c.Item2);
        foreach (var r in rows) table.Rows.Add(r.MetricType, r.ServerId, Db(r.DatabaseId), Db(r.EntityKey), Db(r.DayOfWeek), Db(r.HourOfDay), r.WindowDays, r.SampleCount, r.MedianValue, r.P75Value, r.P90Value, r.P95Value, r.P99Value, r.MeanValue, r.StdDevValue, r.MadValue, r.MinValue, r.MaxValue, r.CalculatedAtUtc, r.ValidFromUtc, r.Status, r.BaselineScope);
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, "dbo.usp_Baselines_Replace"); command.Parameters.Add(new SqlParameter("@Rows", SqlDbType.Structured) { TypeName = "dbo.BaselineInputType", Value = table }); command.Parameters.Add(new SqlParameter("@CalculatedAtUtc", SqlDbType.DateTime2) { Value = calculatedAtUtc }); await command.ExecuteScalarAsync(token);
    }

    public async Task<IReadOnlyList<BaselineResult>> LoadBaselinesAsync(CancellationToken token)
    {
        await using var r = await ExecuteAsync("dbo.usp_Baselines_Evaluation_List", _ => { }, token); var result = new List<BaselineResult>();
        while (await r.ReadAsync(token)) result.Add(new(S(r,"MetricType"),Convert.ToInt32(r["ServerId"]),IntNullable(r,"DatabaseId"),N(r,"EntityKey"),IntNullable(r,"DayOfWeek"),IntNullable(r,"HourOfDay"),Convert.ToInt32(r["WindowDays"]),Convert.ToInt32(r["SampleCount"]),Convert.ToDecimal(r["MedianValue"]),Convert.ToDecimal(r["P75Value"]),Convert.ToDecimal(r["P90Value"]),Convert.ToDecimal(r["P95Value"]),Convert.ToDecimal(r["P99Value"]),Convert.ToDecimal(r["MeanValue"]),Convert.ToDecimal(r["StdDevValue"]),Convert.ToDecimal(r["MadValue"]),Convert.ToDecimal(r["MinValue"]),Convert.ToDecimal(r["MaxValue"]),Utc(r,"CalculatedAtUtc").UtcDateTime,Utc(r,"ValidFromUtc").UtcDateTime,S(r,"Status"),S(r,"BaselineScope")));
        return result;
    }

    public async Task<IReadOnlyList<AnomalyPolicy>> PoliciesAsync(CancellationToken token)
    {
        await using var r = await ExecuteAsync("dbo.usp_AnomalyPolicies_List", _ => { }, token); var result = new List<AnomalyPolicy>();
        while (await r.ReadAsync(token)) result.Add(new(S(r,"MetricType"),Convert.ToDecimal(r["WarningPercentile"]),Convert.ToDecimal(r["CriticalPercentile"]),Convert.ToDecimal(r["WarningModifiedZ"]),Convert.ToDecimal(r["CriticalModifiedZ"]),Convert.ToDecimal(r["MinObservedValue"]),Convert.ToBoolean(r["IsEnabled"])));
        return result;
    }

    public async Task<int> ResolveStaleAsync(string metricType, DateTime asOfUtc, int afterSeconds, CancellationToken token)
    {
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, "dbo.usp_Anomalies_ResolveStale"); command.Parameters.AddWithValue("@MetricType", metricType); command.Parameters.Add(new SqlParameter("@AsOfUtc", SqlDbType.DateTime2) { Value = asOfUtc }); command.Parameters.AddWithValue("@AfterSeconds", afterSeconds); return Convert.ToInt32(await command.ExecuteScalarAsync(token));
    }

    public async Task UpsertFindingsAsync(IReadOnlyCollection<AnomalyEvaluation> rows, DateTime asOfUtc, CancellationToken token)
    {
        if (rows.Count == 0) return;
        var table = new DataTable(); foreach (var c in new[] { ("MetricType", typeof(string)), ("ServerId", typeof(int)), ("DatabaseId", typeof(int)), ("EntityKey", typeof(string)), ("ObservedAtUtc", typeof(DateTime)), ("ObservedValue", typeof(decimal)), ("BaselineMedian", typeof(decimal)), ("BaselineP95", typeof(decimal)), ("BaselineP99", typeof(decimal)), ("BaselineMad", typeof(decimal)), ("DeviationRatio", typeof(decimal)), ("ModifiedZScore", typeof(decimal)), ("BaselineScope", typeof(string)), ("SampleCount", typeof(int)), ("Severity", typeof(string)), ("Status", typeof(string)), ("ExplanationCode", typeof(string)), ("Fingerprint", typeof(string)), ("SourceEntityId", typeof(long)) }) table.Columns.Add(c.Item1, c.Item2);
        foreach (var r in rows) table.Rows.Add(r.MetricType, r.ServerId, Db(r.DatabaseId), Db(r.EntityKey), r.ObservedAtUtc, r.ObservedValue, r.BaselineMedian, r.BaselineP95, r.BaselineP99, r.BaselineMad, Db(r.DeviationRatio), Db(r.ModifiedZScore), r.BaselineScope, r.SampleCount, r.Severity, r.Status, r.ExplanationCode, r.Fingerprint, Db(r.SourceEntityId));
        await using var connection = await OpenAsync(token); await using var command = Procedure(connection, "dbo.usp_AnomalyFindings_Upsert"); command.Parameters.Add(new SqlParameter("@Rows", SqlDbType.Structured) { TypeName = "dbo.AnomalyFindingInputType", Value = table }); command.Parameters.Add(new SqlParameter("@AsOfUtc", SqlDbType.DateTime2) { Value = asOfUtc }); await command.ExecuteScalarAsync(token);
    }

    public async Task<AnomalyOverview> OverviewAsync(CancellationToken token) { await using var r = await ExecuteAsync("dbo.usp_Anomalies_Overview", _ => { }, token); await r.ReadAsync(token); return new(Convert.ToInt32(r["ActiveAnomalyCount"]), Convert.ToInt32(r["ActiveCriticalCount"]), Convert.ToInt32(r["ActiveWarningCount"]), Convert.ToInt32(r["ResolvedAnomalyCount"]), Convert.ToInt32(r["UsableBaselineCount"]), Convert.ToInt32(r["InsufficientBaselineCount"]), Convert.ToInt32(r["EntitiesWithAnomalies"])); }

    public async Task<PagedResult<AnomalyRow>> AnomaliesAsync(string? metricType, string? severity, string? status, int? serverId, int? databaseId, DateTimeOffset? fromUtc, DateTimeOffset? toUtc, int page, int pageSize, CancellationToken token)
    {
        await using var r = await ExecuteAsync("dbo.usp_Anomalies_List", c => { Param(c, "@MetricType", Limit(metricType, 64)); Param(c, "@Severity", Limit(severity, 20)); Param(c, "@Status", Limit(status, 20)); Param(c, "@ServerId", serverId); Param(c, "@DatabaseId", databaseId); Date(c, "@FromUtc", fromUtc); Date(c, "@ToUtc", toUtc); c.Parameters.AddWithValue("@Page", Math.Max(1, page)); c.Parameters.AddWithValue("@PageSize", Math.Clamp(pageSize, 1, 100)); }, token);
        var items = new List<AnomalyRow>(); while (await r.ReadAsync(token)) items.Add(new(Convert.ToInt64(r["Id"]), S(r,"MetricType"), S(r,"ServerName"), N(r,"DatabaseName"), N(r,"EntityKey"), Utc(r,"ObservedAtUtc"), Convert.ToDecimal(r["ObservedValue"]), Convert.ToDecimal(r["BaselineMedian"]), Convert.ToDecimal(r["BaselineP95"]), DecimalNullable(r,"DeviationRatio"), DecimalNullable(r,"ModifiedZScore"), S(r,"BaselineScope"), Convert.ToInt32(r["SampleCount"]), S(r,"Severity"), S(r,"Status"), S(r,"ExplanationCode"), Utc(r,"StartedAtUtc"), Utc(r,"LastSeenAtUtc")));
        var total = await r.NextResultAsync(token) && await r.ReadAsync(token) ? Convert.ToInt32(r["TotalCount"]) : 0; return new(items, page, Math.Clamp(pageSize,1,100), total);
    }

    public async Task<AnomalyDetail?> AnomalyDetailAsync(long id, CancellationToken token) { await using var r = await ExecuteAsync("dbo.usp_Anomaly_Detail", c => c.Parameters.AddWithValue("@Id", id), token); return await r.ReadAsync(token) ? new(Convert.ToInt64(r["Id"]),S(r,"MetricType"),S(r,"ServerName"),N(r,"DatabaseName"),N(r,"EntityKey"),Utc(r,"ObservedAtUtc"),Convert.ToDecimal(r["ObservedValue"]),Convert.ToDecimal(r["BaselineMedian"]),Convert.ToDecimal(r["BaselineP95"]),Convert.ToDecimal(r["BaselineP99"]),Convert.ToDecimal(r["BaselineMad"]),DecimalNullable(r,"DeviationRatio"),DecimalNullable(r,"ModifiedZScore"),S(r,"BaselineScope"),Convert.ToInt32(r["SampleCount"]),Convert.ToInt32(r["WindowDays"]),S(r,"Severity"),S(r,"Status"),S(r,"ExplanationCode"),Utc(r,"StartedAtUtc"),Utc(r,"LastSeenAtUtc"),UtcNullable(r,"EndedAtUtc"),Convert.ToInt32(r["ObservationCount"]),LongNullable(r,"SourceEntityId"),S(r,"Fingerprint")) : null; }

    public async Task<PagedResult<BaselineRow>> BaselinesAsync(string? metricType, string? status, int? serverId, int? databaseId, int page, int pageSize, CancellationToken token)
    {
        await using var r = await ExecuteAsync("dbo.usp_Baselines_List", c => { Param(c,"@MetricType",Limit(metricType,64)); Param(c,"@Status",Limit(status,24)); Param(c,"@ServerId",serverId); Param(c,"@DatabaseId",databaseId); c.Parameters.AddWithValue("@Page",Math.Max(1,page)); c.Parameters.AddWithValue("@PageSize",Math.Clamp(pageSize,1,100)); }, token);
        var items = new List<BaselineRow>(); while (await r.ReadAsync(token)) items.Add(new(Convert.ToInt64(r["Id"]),S(r,"MetricType"),S(r,"ServerName"),N(r,"DatabaseName"),N(r,"EntityKey"),IntNullable(r,"DayOfWeek"),IntNullable(r,"HourOfDay"),Convert.ToInt32(r["WindowDays"]),Convert.ToInt32(r["SampleCount"]),Convert.ToDecimal(r["MedianValue"]),Convert.ToDecimal(r["P90Value"]),Convert.ToDecimal(r["P95Value"]),Convert.ToDecimal(r["P99Value"]),Convert.ToDecimal(r["MadValue"]),Convert.ToDecimal(r["MeanValue"]),Convert.ToDecimal(r["StdDevValue"]),S(r,"BaselineScope"),Utc(r,"CalculatedAtUtc"),S(r,"Status"))); var total = await r.NextResultAsync(token) && await r.ReadAsync(token) ? Convert.ToInt32(r["TotalCount"]) : 0; return new(items,page,Math.Clamp(pageSize,1,100),total);
    }
    public async Task<BaselineRow?> BaselineDetailAsync(long id, CancellationToken token) { await using var r = await ExecuteAsync("dbo.usp_Baseline_Detail", c => c.Parameters.AddWithValue("@Id",id), token); return await r.ReadAsync(token) ? new(Convert.ToInt64(r["Id"]),S(r,"MetricType"),S(r,"ServerName"),N(r,"DatabaseName"),N(r,"EntityKey"),IntNullable(r,"DayOfWeek"),IntNullable(r,"HourOfDay"),Convert.ToInt32(r["WindowDays"]),Convert.ToInt32(r["SampleCount"]),Convert.ToDecimal(r["MedianValue"]),Convert.ToDecimal(r["P90Value"]),Convert.ToDecimal(r["P95Value"]),Convert.ToDecimal(r["P99Value"]),Convert.ToDecimal(r["MadValue"]),Convert.ToDecimal(r["MeanValue"]),Convert.ToDecimal(r["StdDevValue"]),S(r,"BaselineScope"),Utc(r,"CalculatedAtUtc"),S(r,"Status")) : null; }

    private async Task<SqlDataReader> ExecuteAsync(string procedure, Action<SqlCommand> configure, CancellationToken token) { var c = await OpenAsync(token); var command = Procedure(c, procedure); configure(command); return await command.ExecuteReaderAsync(CommandBehavior.CloseConnection, token); }
    private async Task<SqlConnection> OpenAsync(CancellationToken token) { var c = new SqlConnection(_connectionString); await c.OpenAsync(token); return c; }
    private static SqlCommand Procedure(SqlConnection c,string name)=>new(name,c){CommandType=CommandType.StoredProcedure,CommandTimeout=60};
    private static void Param(SqlCommand c,string name,object? value)=>c.Parameters.AddWithValue(name,value??DBNull.Value); private static void Date(SqlCommand c,string name,DateTimeOffset? value)=>c.Parameters.Add(new SqlParameter(name,SqlDbType.DateTime2){Value=(object?)value?.UtcDateTime??DBNull.Value}); private static object? Limit(string? value,int max)=>string.IsNullOrWhiteSpace(value)?null:value[..Math.Min(value.Length,max)]; private static object Db(object? v)=>v??DBNull.Value;
    private static string S(SqlDataReader r,string n)=>Convert.ToString(r[n])??string.Empty; private static string? N(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Convert.ToString(r[n]); private static string? N(SqlDataReader r,int i)=>r.IsDBNull(i)?null:Convert.ToString(r.GetValue(i)); private static string S(SqlDataReader r,int i)=>Convert.ToString(r.GetValue(i))??string.Empty; private static int? IntNullable(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Convert.ToInt32(r[n]); private static int? IntNullable(SqlDataReader r,int i)=>r.IsDBNull(i)?null:Convert.ToInt32(r.GetValue(i)); private static long? LongNullable(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Convert.ToInt64(r[n]); private static long? LongNullable(SqlDataReader r,int i)=>r.IsDBNull(i)?null:Convert.ToInt64(r.GetValue(i)); private static decimal? DecimalNullable(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Convert.ToDecimal(r[n]); private static DateTimeOffset Utc(SqlDataReader r,string n)=>new(DateTime.SpecifyKind(Convert.ToDateTime(r[n]),DateTimeKind.Utc)); private static DateTimeOffset Utc(SqlDataReader r,int i)=>new(DateTime.SpecifyKind(Convert.ToDateTime(r.GetValue(i)),DateTimeKind.Utc)); private static DateTimeOffset? UtcNullable(SqlDataReader r,string n)=>r.IsDBNull(r.GetOrdinal(n))?null:Utc(r,n);
}
