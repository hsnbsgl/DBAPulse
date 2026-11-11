using DBAPulse.Data;
using DBAPulse.Domain;

namespace DBAPulse.Collector;

public sealed class AnomalyEngine
{
    private readonly ManagementStore _management;
    private readonly BaselineStore _store;
    private readonly BaselineCalculator _calculator = new();
    private readonly AnomalyDetector _detector = new();
    private readonly int _windowDays;
    private readonly int _minimumSamples;
    private readonly int _minimumDays;
    private readonly string _timeZone;
    private readonly TimeZoneInfo _zone;
    private readonly TimeSpan _recalculationInterval;
    private readonly int _resolveAfterSeconds;
    private DateTime _lastCalculatedAtUtc = DateTime.MinValue;
    private static readonly Dictionary<string, TimeSpan> BucketedMetrics = new(StringComparer.OrdinalIgnoreCase) { ["BlockingFrequency"] = TimeSpan.FromHours(1) };

    public AnomalyEngine(ManagementStore management, BaselineStore store, IConfiguration configuration)
    {
        _management = management; _store = store; _windowDays = Math.Max(1, Int(configuration["DBAPULSE_BASELINE_WINDOW_DAYS"], 30)); _minimumSamples = Math.Max(1, Int(configuration["DBAPULSE_BASELINE_MIN_SAMPLES"], 20)); _minimumDays = Math.Max(1, Int(configuration["DBAPULSE_BASELINE_MIN_DAYS"], 7)); _timeZone = configuration["DBAPULSE_DISPLAY_TIMEZONE"] ?? "Europe/Istanbul"; _recalculationInterval = TimeSpan.FromHours(Math.Max(1, Int(configuration["DBAPULSE_BASELINE_RECALC_INTERVAL_HOURS"], 6))); _resolveAfterSeconds = Math.Max(1, Int(configuration["DBAPULSE_ANOMALY_RESOLVE_AFTER_SECONDS"], 900));
        try { _zone = TimeZoneInfo.FindSystemTimeZoneById(_timeZone); } catch { _zone = TimeZoneInfo.Utc; }
    }

    public async Task<IReadOnlyList<AnomalyEvaluation>> EvaluateAsync(DateTime asOfUtc, CancellationToken token)
    {
        var enabledServers = await _management.GetAnomalyTrackingServerIdsAsync(token);
        var samples = (await _store.SamplesAsync(asOfUtc.AddDays(-_windowDays), asOfUtc, token)).Where(x => enabledServers.Contains(x.ServerId)).ToArray();
        IReadOnlyList<BaselineResult> baselines;
        if (asOfUtc - _lastCalculatedAtUtc >= _recalculationInterval)
        {
            baselines = _calculator.Calculate(samples, asOfUtc, _windowDays, _minimumSamples, _minimumDays, _timeZone);
            await _store.ReplaceBaselinesAsync(baselines, asOfUtc, token); _lastCalculatedAtUtc = asOfUtc;
        }
        else baselines = await _store.LoadBaselinesAsync(token);
        var policies = (await _store.PoliciesAsync(token)).ToDictionary(x => x.MetricType, StringComparer.OrdinalIgnoreCase);
        var output = new List<AnomalyEvaluation>();
        var usable = new Dictionary<(string Metric, int Server, int? Database, string? Entity, string Scope, int? DayOfWeek, int? Hour), BaselineResult>();
        foreach (var baseline in baselines.Where(x => x.Status == "Usable" && (x.BaselineScope == "Seasonal" || x.BaselineScope == "Global")))
            usable.TryAdd(BaselineKey(baseline.MetricType, baseline.ServerId, baseline.DatabaseId, baseline.EntityKey, baseline.BaselineScope, baseline.BaselineScope == "Seasonal" ? baseline.DayOfWeek : null, baseline.BaselineScope == "Seasonal" ? baseline.HourOfDay : null), baseline);
        // Only evaluate samples observed inside the resolve window; older "latest" samples would otherwise reopen stale anomalies every cycle.
        // Bucketed metrics are stamped with the bucket start, so they stay fresh until their bucket ends.
        var freshFromUtc = asOfUtc.AddSeconds(-_resolveAfterSeconds);
        foreach (var current in samples.Where(x => x.ObservedAtUtc.UtcDateTime + (BucketedMetrics.TryGetValue(x.MetricType, out var bucketLength) ? bucketLength : TimeSpan.Zero) >= freshFromUtc).GroupBy(x => (x.MetricType, x.ServerId, x.DatabaseId, x.EntityKey)).Select(x => x.OrderByDescending(v => v.ObservedAtUtc).First()))
        {
            if (!policies.TryGetValue(current.MetricType, out var policy)) continue;
            var bucket = LocalBucket(current.ObservedAtUtc);
            usable.TryGetValue(BaselineKey(current.MetricType, current.ServerId, current.DatabaseId, current.EntityKey, "Seasonal", bucket.DayOfWeek, bucket.Hour), out var seasonal);
            usable.TryGetValue(BaselineKey(current.MetricType, current.ServerId, current.DatabaseId, current.EntityKey, "Global", null, null), out var global);
            var evaluation = _detector.Evaluate(current, seasonal ?? global, policy);
            if (evaluation is not null) output.Add(evaluation);
        }
        foreach (var metric in samples.Select(x => x.MetricType).Distinct()) await _store.ResolveStaleAsync(metric, asOfUtc, _resolveAfterSeconds, token);
        await _store.UpsertFindingsAsync(output, asOfUtc, token);
        return output;
    }

    // Case-insensitive on metric/entity, matching the previous OrdinalIgnoreCase comparison.
    private static (string Metric, int Server, int? Database, string? Entity, string Scope, int? DayOfWeek, int? Hour) BaselineKey(string metric, int server, int? database, string? entity, string scope, int? dayOfWeek, int? hour)
        => (metric.ToUpperInvariant(), server, database, entity?.ToUpperInvariant(), scope, dayOfWeek, hour);
    private (int DayOfWeek, int Hour) LocalBucket(DateTimeOffset value) { var local = TimeZoneInfo.ConvertTime(value, _zone); return ((int)local.DayOfWeek, local.Hour); }
    private static int Int(string? value, int fallback) => int.TryParse(value, out var parsed) ? parsed : fallback;
}
