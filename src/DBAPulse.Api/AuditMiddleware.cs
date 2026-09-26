using System.Diagnostics;
using System.Text.Json;
using DBAPulse.Data;
using DBAPulse.Domain;

namespace DBAPulse.Api;

public sealed class AuditMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<AuditMiddleware> _logger;
    private readonly AuditStore _store;
    public AuditMiddleware(RequestDelegate next, ILogger<AuditMiddleware> logger, AuditStore store) { _next = next; _logger = logger; _store = store; }

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = GetCorrelationId(context.Request.Headers["X-Correlation-ID"].FirstOrDefault());
        context.Response.Headers["X-Correlation-ID"] = correlationId;
        if (!TryDescribe(context, out var action, out var resourceType, out var resourceId, out var additionalData))
        {
            await _next(context);
            return;
        }

        var stopwatch = Stopwatch.StartNew(); var statusCode = StatusCodes.Status200OK; var result = "Success";
        try
        {
            await _next(context);
            statusCode = context.Response.StatusCode;
            result = statusCode >= 400 ? "Failed" : "Success";
        }
        catch (Exception ex)
        {
            statusCode = StatusCodes.Status500InternalServerError; result = "Failed";
            _logger.LogError(ex, "Audited request failed: {Action} {Path} CorrelationId={CorrelationId}", action, context.Request.Path, correlationId);
            throw;
        }
        finally
        {
            stopwatch.Stop();
            var userName = context.User.Identity?.IsAuthenticated == true ? context.User.Identity.Name ?? "authenticated" : "anonymous"; var userRole = context.User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value ?? "Unauthenticated";
            var entry = new AuditLogEntry(0, DateTimeOffset.UtcNow, userName, userRole, action, resourceType, resourceId,
                context.Request.Method, Limit(context.Request.Path.Value, 512)!, result, statusCode, stopwatch.ElapsedMilliseconds, correlationId,
                Limit(context.Connection.RemoteIpAddress?.ToString(), 128), Limit(context.Request.Headers.UserAgent.FirstOrDefault(), 512), additionalData);
            try { await _store.InsertAsync(entry, CancellationToken.None); }
            catch (Exception ex) { _logger.LogError(ex, "Audit write failed for {Action} CorrelationId={CorrelationId}", action, correlationId); }
        }
    }

    private static bool TryDescribe(HttpContext context, out string action, out string resourceType, out string? resourceId, out string? additionalData)
    {
        action = string.Empty; resourceType = string.Empty; resourceId = null; additionalData = null;
        var path = context.Request.Path.Value ?? string.Empty;
        if (!HttpMethods.IsGet(context.Request.Method) && !path.StartsWith("/api/settings", StringComparison.OrdinalIgnoreCase)) return false;
        if (path.Equals("/api/health", StringComparison.OrdinalIgnoreCase)) return false;
        var parts = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || !parts[0].Equals("api", StringComparison.OrdinalIgnoreCase)) return false;
        if (parts[1].Equals("settings", StringComparison.OrdinalIgnoreCase))
        {
            resourceType = "Settings";
            var scope = parts.Length >= 3 ? parts[2].ToLowerInvariant() : "general";
            resourceId = scope == "servers" && parts.Length >= 4 ? Numeric(parts[3]) : null;
            action = HttpMethods.IsGet(context.Request.Method) ? $"Settings.{scope}.View" : context.Request.Method == HttpMethods.Post ? $"Settings.{scope}.Test" : $"Settings.{scope}.Update";
            return true;
        }
        if (parts[1].Equals("management", StringComparison.OrdinalIgnoreCase)) { resourceType="Management"; action=parts.Length>=3 ? parts[2].Equals("attention",StringComparison.OrdinalIgnoreCase) ? "Management.Attention.View" : parts[2].Equals("health",StringComparison.OrdinalIgnoreCase) ? "Management.Health.View" : parts[2].Equals("changes",StringComparison.OrdinalIgnoreCase) ? "Management.Changes.View" : parts[2].Equals("correlations",StringComparison.OrdinalIgnoreCase) ? (parts.Length>=4 ? "Management.Correlation.Detail" : "Management.Correlation.List") : "Management.View" : "Management.View"; return true; }
        if (parts[1].Equals("dashboard", StringComparison.OrdinalIgnoreCase) && parts.Length >= 3) { action = "Dashboard.View"; resourceType = "Dashboard"; return true; }
        if (parts[1].Equals("performance", StringComparison.OrdinalIgnoreCase) && parts.Length >= 3)
        {
            action = parts[2].Equals("overview", StringComparison.OrdinalIgnoreCase) ? "Performance.View" : parts[2].ToLowerInvariant() switch
            {
                "blocking" => "Performance.Blocking.View",
                "deadlocks" => "Performance.Deadlock.View",
                "long-running" => "Performance.LongRunning.View",
                "waits" => "Performance.Waits.View",
                _ => "Performance.View"
            };
            resourceType = "Performance"; return true;
        }
        if (parts[1].Equals("operations", StringComparison.OrdinalIgnoreCase) && parts.Length >= 3)
        {
            action = parts[2].Equals("overview", StringComparison.OrdinalIgnoreCase) ? "Operations.View" : parts.Length >= 4 ? "Operations.EventDetail.View" : "Operations.EventList.View";
            resourceType = "Operations"; resourceId = parts.Length >= 4 ? Numeric(parts[3]) : null; return true;
        }
        if (parts[1].Equals("protection", StringComparison.OrdinalIgnoreCase) && parts.Length >= 3)
        {
            action = parts[2].Equals("overview", StringComparison.OrdinalIgnoreCase) ? "Protection.View" : parts.Length >= 4 ? "Protection.BackupDetail.View" : "Protection.BackupList.View";
            resourceType = "Protection"; resourceId = parts.Length >= 4 ? Numeric(parts[3]) : null; return true;
        }
        if (parts[1].Equals("availability", StringComparison.OrdinalIgnoreCase) && parts.Length >= 3)
        {
            action = parts.Length >= 4 ? "Availability.AlwaysOnDetail.View" : "Availability.AlwaysOn.View";
            resourceType = "Availability"; resourceId = parts.Length >= 4 ? Numeric(parts[3]) : null; return true;
        }
        if (parts[1].Equals("jobs", StringComparison.OrdinalIgnoreCase) && parts.Length >= 2)
        {
            action = parts.Length >= 3 ? "Jobs.Detail.View" : "Jobs.View"; resourceType = "Job"; resourceId = parts.Length >= 3 ? Numeric(parts[2]) : null; return true;
        }
        if (parts[1].Equals("capacity", StringComparison.OrdinalIgnoreCase) && parts.Length >= 3)
        {
            resourceType = "Capacity";
            if (parts[2].Equals("overview", StringComparison.OrdinalIgnoreCase)) { action = "Capacity.View"; return true; }
            if (parts[2].Equals("databases", StringComparison.OrdinalIgnoreCase)) { resourceId = parts.Length >= 4 ? Numeric(parts[3]) : null; action = parts.Length >= 5 ? "Capacity.DatabaseHistory.View" : resourceId is null ? "Capacity.DatabaseList.View" : "Capacity.DatabaseDetail.View"; return true; }
            if (parts[2].Equals("volumes", StringComparison.OrdinalIgnoreCase)) { action = parts.Length >= 4 ? "Capacity.VolumeDetail.View" : "Capacity.VolumeList.View"; return true; }
        }
        if (parts[1].Equals("collections", StringComparison.OrdinalIgnoreCase)) { action = "Collection.List"; resourceType = "Collection"; return true; }
        if (parts[1].Equals("audit", StringComparison.OrdinalIgnoreCase)) { action = "Audit.List"; resourceType = "Audit"; return true; }
        if (parts[1].Equals("anomalies", StringComparison.OrdinalIgnoreCase)) { action = parts.Length >= 3 ? "Anomaly.Detail.View" : "Anomaly.List.View"; resourceType = "Anomaly"; resourceId = parts.Length >= 3 ? Numeric(parts[2]) : null; return true; }
        if (parts[1].Equals("baselines", StringComparison.OrdinalIgnoreCase)) { action = parts.Length >= 3 ? "Baseline.Detail.View" : "Baseline.List.View"; resourceType = "Baseline"; resourceId = parts.Length >= 3 ? Numeric(parts[2]) : null; return true; }
        if (parts[1].Equals("servers", StringComparison.OrdinalIgnoreCase))
        {
            resourceType = "Server"; resourceId = parts.Length >= 3 ? Numeric(parts[2]) : null; action = resourceId is null ? "Server.List" : "Server.View"; return true;
        }
        if (parts[1].Equals("databases", StringComparison.OrdinalIgnoreCase))
        {
            resourceType = "Database"; resourceId = parts.Length >= 3 ? Numeric(parts[2]) : null;
            if (parts.Length >= 4 && parts[3].Equals("capacity-history", StringComparison.OrdinalIgnoreCase)) { action = "Database.CapacityHistory.View"; additionalData = JsonSerializer.Serialize(new { days = AllowedDays(context.Request.Query["days"]) }); return true; }
            action = resourceId is null ? "Database.List" : "Database.View"; return true;
        }
        return false;
    }
    private static string GetCorrelationId(string? value) => Guid.TryParse(value, out var id) ? id.ToString() : Guid.NewGuid().ToString();
    private static string? Numeric(string value) => int.TryParse(value, out _) ? value : null;
    private static int AllowedDays(string? value) => int.TryParse(value, out var days) && new[] { 7, 30, 90, 180, 365 }.Contains(days) ? days : 30;
    private static string? Limit(string? value, int max) => string.IsNullOrWhiteSpace(value) ? null : value[..Math.Min(value.Length, max)];
}
