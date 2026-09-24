using DBAPulse.Data;
using DBAPulse.Domain;

namespace DBAPulse.Collector;

public sealed class AnomalyEngine
{
    private readonly BaselineStore _store;
    private readonly BaselineCalculator _calculator = new();
    private readonly AnomalyDetector _detector = new();
    private readonly int _windowDays;
    private readonly int _minimumSamples;
    private readonly int _minimumDays;
    private readonly string _timeZone;
    private readonly TimeSpan _recalculationInterval;
    private readonly int _resolveAfterSeconds;
    private DateTime _lastCalculatedAtUtc = DateTime.MinValue;

    public AnomalyEngine(BaselineStore store, IConfiguration configuration)
    {
        _store = store; _windowDays = Math.Max(1, Int(configuration["DBAPULSE_BASELINE_WINDOW_DAYS"], 30)); _minimumSamples = Math.Max(1, Int(configuration["DBAPULSE_BASELINE_MIN_SAMPLES"], 20)); _minimumDays = Math.Max(1, Int(configuration["DBAPULSE_BASELINE_MIN_DAYS"], 7)); _timeZone = configuration["DBAPULSE_DISPLAY_TIMEZONE"] ?? "Europe/Istanbul"; _recalculationInterval = TimeSpan.FromHours(Math.Max(1, Int(configuration["DBAPULSE_BASELINE_RECALC_INTERVAL_HOURS"], 6))); _resolveAfterSeconds = Math.Max(1, Int(configuration["DBAPULSE_ANOMALY_RESOLVE_AFTER_SECONDS"], 900));
    }

    public async Task<IReadOnlyList<AnomalyEvaluation>> EvaluateAsync(DateTime asOfUtc, CancellationToken token)
    {
        var samples = await _store.SamplesAsync(asOfUtc.AddDays(-_windowDays), asOfUtc, token);
        IReadOnlyList<BaselineResult> baselines;
        if (asOfUtc - _lastCalculatedAtUtc >= _recalculationInterval)
        {
            baselines = _calculator.Calculate(samples, asOfUtc, _windowDays, _minimumSamples, _minimumDays, _timeZone);
            await _store.ReplaceBaselinesAsync(baselines, asOfUtc, token); _lastCalculatedAtUtc = asOfUtc;
        }
        else baselines = await _store.LoadBaselinesAsync(token);
        var policies = (await _store.PoliciesAsync(token)).ToDictionary(x => x.MetricType, StringComparer.OrdinalIgnoreCase);
        var output = new List<AnomalyEvaluation>();
        foreach (var current in samples.GroupBy(x => (x.MetricType, x.ServerId, x.DatabaseId, x.EntityKey)).Select(x => x.OrderByDescending(v => v.ObservedAtUtc).First()))
        {
            if (!policies.TryGetValue(current.MetricType, out var policy)) continue;
            var seasonal = baselines.FirstOrDefault(x => SameKey(x, current) && x.BaselineScope == "Seasonal" && x.DayOfWeek == LocalBucket(current.ObservedAtUtc).DayOfWeek && x.HourOfDay == LocalBucket(current.ObservedAtUtc).Hour && x.Status == "Usable");
            var global = baselines.FirstOrDefault(x => SameKey(x, current) && x.BaselineScope == "Global" && x.Status == "Usable");
            var evaluation = _detector.Evaluate(current, seasonal ?? global, policy);
            if (evaluation is not null) output.Add(evaluation);
        }
        foreach (var metric in samples.Select(x => x.MetricType).Distinct()) await _store.ResolveStaleAsync(metric, asOfUtc, _resolveAfterSeconds, token);
        await _store.UpsertFindingsAsync(output, asOfUtc, token);
        return output;
    }

    private bool SameKey(BaselineResult baseline, AnomalySample sample) => baseline.MetricType.Equals(sample.MetricType, StringComparison.OrdinalIgnoreCase) && baseline.ServerId == sample.ServerId && baseline.DatabaseId == sample.DatabaseId && string.Equals(baseline.EntityKey, sample.EntityKey, StringComparison.OrdinalIgnoreCase);
    private (int DayOfWeek, int Hour) LocalBucket(DateTimeOffset value) { TimeZoneInfo zone; try { zone = TimeZoneInfo.FindSystemTimeZoneById(_timeZone); } catch { zone = TimeZoneInfo.Utc; } var local = TimeZoneInfo.ConvertTime(value, zone); return ((int)local.DayOfWeek, local.Hour); }
    private static int Int(string? value, int fallback) => int.TryParse(value, out var parsed) ? parsed : fallback;
}
