using DBAPulse.Domain;
using DBAPulse.Data;
using DBAPulse.Api;

var builder = WebApplication.CreateBuilder(args);
var apiConnection = builder.Configuration["DBAPULSE_API_CONNECTION"];
if (string.IsNullOrWhiteSpace(apiConnection)) throw new InvalidOperationException("DBAPULSE_API_CONNECTION is required.");

builder.Services.AddSingleton(new DashboardStore(apiConnection));
builder.Services.AddSingleton(new AuditStore(apiConnection));
builder.Services.AddSingleton(new PerformanceStore(apiConnection));
builder.Services.AddSingleton(new OperationsStore(apiConnection));
builder.Services.AddSingleton(new ProtectionStore(apiConnection));
builder.Services.AddSingleton(new CapacityStore(apiConnection));
builder.Services.AddSingleton(new BaselineStore(apiConnection));
builder.Services.AddSingleton(new ManagementReadStore(apiConnection));
builder.Services.AddProblemDetails();
builder.Services.AddCors(options => options.AddPolicy("Development", policy => policy.WithOrigins("http://localhost:5173").AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();
app.UseExceptionHandler();
if (app.Environment.IsDevelopment()) app.UseCors("Development");
app.UseMiddleware<AuditMiddleware>();

app.MapGet("/api/health", async (DashboardStore store, CancellationToken token) =>
{
    try { return Results.Ok(new { status = "Healthy", database = await store.CanConnectAsync(token) ? "Healthy" : "Unhealthy" }); }
    catch { return Results.Json(new { status = "Unhealthy", database = "Unhealthy" }, statusCode: StatusCodes.Status503ServiceUnavailable); }
});
app.MapGet("/api/dashboard/overview", async (DashboardStore store, CancellationToken token) => Results.Ok(await store.GetOverviewAsync(token)));
app.MapGet("/api/dashboard/database-health", async (DashboardStore store, CancellationToken token) => Results.Ok(await store.GetHealthAsync(token)));
app.MapGet("/api/dashboard/backup-status", async (DashboardStore store, CancellationToken token) => Results.Ok(await store.GetBackupStatusAsync(token)));
app.MapGet("/api/dashboard/capacity", async (DashboardStore store, CancellationToken token) => { var value = await store.GetCapacityAsync(token); return Results.Ok(new { summary = value.Summary, items = value.Items }); });
app.MapGet("/api/collections/recent", async (int? limit, DashboardStore store, CancellationToken token) => Results.Ok(await store.GetRecentCollectionsAsync(Math.Clamp(limit ?? 20, 1, 100), token)));
app.MapGet("/api/servers", async (DashboardStore store, CancellationToken token) => Results.Ok(await store.GetServersAsync(token)));
app.MapGet("/api/servers/{id:int}", async (int id, DashboardStore store, CancellationToken token) => { var value = await store.GetServerDetailAsync(id, token); return value.Server is null ? Results.NotFound() : Results.Ok(value); });
app.MapGet("/api/databases", async (int? page, int? pageSize, string? search, DashboardStore store, CancellationToken token) => Results.Ok(await store.GetDatabasesAsync(Math.Max(1, page ?? 1), Math.Clamp(pageSize ?? 50, 1, 100), search, token)));
app.MapGet("/api/databases/{id:int}", async (int id, DashboardStore store, CancellationToken token) => { var value = await store.GetDatabaseDetailAsync(id, token); return value is null ? Results.NotFound() : Results.Ok(value); });
app.MapGet("/api/databases/{id:int}/capacity-history", async (int id, int? days, DashboardStore store, CancellationToken token) => Results.Ok(await store.GetCapacityHistoryAsync(id, days ?? 30, token)));
app.MapGet("/api/audit", async (DateTimeOffset? fromUtc, DateTimeOffset? toUtc, string? userName, string? action, string? resourceType, string? result, string? correlationId, int? page, int? pageSize, AuditStore store, CancellationToken token) =>
    Results.Ok(await store.ListAsync(fromUtc, toUtc, userName, action, resourceType, result, correlationId, Math.Max(1, page ?? 1), Math.Clamp(pageSize ?? 50, 1, 100), token)));
app.MapGet("/api/performance/overview", async (int? hours, PerformanceStore store, CancellationToken token) => Results.Ok(await store.GetOverviewAsync(PerformanceStore.AllowedHours(hours ?? 24), token)));
app.MapGet("/api/performance/blocking", async (int? hours, PerformanceStore store, CancellationToken token) => Results.Ok(await store.GetBlockingAsync(PerformanceStore.AllowedHours(hours ?? 24), token)));
app.MapGet("/api/performance/deadlocks", async (int? hours, PerformanceStore store, CancellationToken token) => Results.Ok(await store.GetDeadlocksAsync(PerformanceStore.AllowedHours(hours ?? 24), token)));
app.MapGet("/api/performance/long-running", async (int? hours, PerformanceStore store, CancellationToken token) => Results.Ok(await store.GetLongRunningAsync(PerformanceStore.AllowedHours(hours ?? 24), token)));
app.MapGet("/api/performance/waits", async (int? hours, PerformanceStore store, CancellationToken token) => Results.Ok(await store.GetWaitsAsync(PerformanceStore.AllowedHours(hours ?? 24), token)));
app.MapGet("/api/operations/overview", async (int? hours, OperationsStore store, CancellationToken token) => Results.Ok(await store.GetOverviewAsync(OperationsStore.AllowedHours(hours ?? 24), token)));
app.MapGet("/api/operations/events", async (DateTimeOffset? fromUtc, DateTimeOffset? toUtc, string? status, string? severity, string? eventType, int? serverId, int? databaseId, int? page, int? pageSize, OperationsStore store, CancellationToken token) => Results.Ok(await store.ListAsync(fromUtc, toUtc, status, severity, eventType, serverId, databaseId, Math.Max(1, page ?? 1), Math.Clamp(pageSize ?? 50, 1, 100), token)));
app.MapGet("/api/operations/events/{id:long}", async (long id, OperationsStore store, CancellationToken token) => { var value = await store.DetailAsync(id, token); return value is null ? Results.NotFound() : Results.Ok(value); });
app.MapGet("/api/protection/overview", async (ProtectionStore store, CancellationToken token) => Results.Ok(await store.OverviewAsync(token)));
app.MapGet("/api/protection/backups", async (string? status, int? serverId, int? databaseId, string? recoveryModel, int? page, int? pageSize, ProtectionStore store, CancellationToken token) => Results.Ok(await store.BackupsAsync(status, serverId, databaseId, recoveryModel, Math.Max(1,page??1), Math.Clamp(pageSize??50,1,100), token)));
app.MapGet("/api/protection/backups/{databaseId:int}", async (int databaseId, ProtectionStore store, CancellationToken token) => Results.Ok(await store.BackupsAsync(null,null,databaseId,null,1,1,token)));
app.MapGet("/api/availability/alwayson", async (string? health, int? serverId, string? role, string? synchronizationState, int? page, int? pageSize, ProtectionStore store, CancellationToken token) => Results.Ok(await store.AlwaysOnAsync(health,serverId,role,synchronizationState,Math.Max(1,page??1),Math.Clamp(pageSize??50,1,100),token)));
app.MapGet("/api/availability/alwayson/{id:long}", async (long id, ProtectionStore store, CancellationToken token) => Results.Ok(await store.AlwaysOnAsync(null,null,null,null,1,1,token,id)));
app.MapGet("/api/jobs", async (string? status, int? serverId, bool? enabled, bool? repeatedFailure, bool? running, int? page, int? pageSize, ProtectionStore store, CancellationToken token) => Results.Ok(await store.JobsAsync(status,serverId,enabled,repeatedFailure,running,Math.Max(1,page??1),Math.Clamp(pageSize??50,1,100),token)));
app.MapGet("/api/jobs/{id:long}", async (long id, ProtectionStore store, CancellationToken token) => Results.Ok(await store.JobsAsync(null,null,null,null,null,1,1,token,id)));
app.MapGet("/api/capacity/overview", async (CapacityStore store, CancellationToken token) => Results.Ok(await store.OverviewAsync(token)));
app.MapGet("/api/capacity/databases", async (string? status, int? serverId, string? forecastStatus, int? page, int? pageSize, CapacityStore store, CancellationToken token) => Results.Ok(await store.DatabasesAsync(status,serverId,forecastStatus,Math.Max(1,page??1),Math.Clamp(pageSize??50,1,100),token)));
app.MapGet("/api/capacity/databases/{id:int}", async (int id, CapacityStore store, CancellationToken token) => Results.Ok(await store.DatabasesAsync(null,null,null,1,1,token,id)));
app.MapGet("/api/capacity/databases/{id:int}/history", async (int id, int? days, CapacityStore store, CancellationToken token) => Results.Ok(await store.HistoryAsync(id,days??30,token)));
app.MapGet("/api/capacity/volumes", async (string? status, int? serverId, string? forecastStatus, int? page, int? pageSize, CapacityStore store, CancellationToken token) => Results.Ok(await store.VolumesAsync(status,serverId,forecastStatus,Math.Max(1,page??1),Math.Clamp(pageSize??50,1,100),token)));
app.MapGet("/api/capacity/volumes/{id}", async (string id, CapacityStore store, CancellationToken token) => Results.Ok(await store.VolumesAsync(null,null,null,1,1,token,id)));
app.MapGet("/api/management/overview", async (ManagementReadStore store, CancellationToken token) => Results.Ok(await store.OverviewAsync(token)));
app.MapGet("/api/management/attention", async (string? severity, int? serverId, int? databaseId, string? domain, int? page, int? pageSize, ManagementReadStore store, CancellationToken token) => Results.Ok(await store.AttentionAsync(severity,serverId,databaseId,domain,Math.Max(1,page??1),Math.Clamp(pageSize??50,1,100),token)));
app.MapGet("/api/management/health", async (int? serverId, int? databaseId, ManagementReadStore store, CancellationToken token) => Results.Ok(await store.HealthAsync(serverId,databaseId,token)));
app.MapGet("/api/management/changes", (DateTimeOffset? fromUtc, DateTimeOffset? toUtc) => Results.Ok(new PagedResult<ManagementChangeRow>(Array.Empty<ManagementChangeRow>(),1,50,0)));
app.MapGet("/api/management/correlations", () => Results.Ok(Array.Empty<CorrelationGroupRow>()));
app.MapGet("/api/management/correlations/{id:long}", (long id) => Results.NotFound());
app.MapGet("/api/anomalies/overview", async (BaselineStore store, CancellationToken token) => Results.Ok(await store.OverviewAsync(token)));
app.MapGet("/api/anomalies", async (string? metricType, string? severity, string? status, int? serverId, int? databaseId, DateTimeOffset? fromUtc, DateTimeOffset? toUtc, int? page, int? pageSize, BaselineStore store, CancellationToken token) => Results.Ok(await store.AnomaliesAsync(metricType, severity, status, serverId, databaseId, fromUtc, toUtc, Math.Max(1, page ?? 1), Math.Clamp(pageSize ?? 50, 1, 100), token)));
app.MapGet("/api/anomalies/{id:long}", async (long id, BaselineStore store, CancellationToken token) => { var value = await store.AnomalyDetailAsync(id, token); return value is null ? Results.NotFound() : Results.Ok(value); });
app.MapGet("/api/baselines", async (string? metricType, string? status, int? serverId, int? databaseId, int? page, int? pageSize, BaselineStore store, CancellationToken token) => Results.Ok(await store.BaselinesAsync(metricType, status, serverId, databaseId, Math.Max(1, page ?? 1), Math.Clamp(pageSize ?? 50, 1, 100), token)));
app.MapGet("/api/baselines/{id:long}", async (long id, BaselineStore store, CancellationToken token) => { var value = await store.BaselineDetailAsync(id, token); return value is null ? Results.NotFound() : Results.Ok(value); });

app.Run();
