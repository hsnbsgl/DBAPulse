using DBAPulse.Domain;

namespace DBAPulse.Data;

public sealed class BaselineCalculator
{
    public IReadOnlyList<BaselineResult> Calculate(IEnumerable<AnomalySample> source, DateTime asOfUtc, int windowDays, int minSamples, int minDays, string timeZoneId)
    {
        var zone = FindTimeZone(timeZoneId);
        var from = asOfUtc.AddDays(-windowDays);
        var samples = source.Where(x => x.ObservedAtUtc.UtcDateTime >= from && x.ObservedAtUtc.UtcDateTime <= asOfUtc).ToArray();
        var results = new List<BaselineResult>();
        foreach (var group in samples.GroupBy(Key))
        {
            results.Add(Build(group.Key, group, null, null, asOfUtc, windowDays, minSamples, minDays, zone, "Global"));
            foreach (var bucket in group.GroupBy(x => Bucket(x.ObservedAtUtc, zone)))
            {
                if (bucket.Count() >= minSamples)
                    results.Add(Build(group.Key, bucket, bucket.Key.DayOfWeek, bucket.Key.Hour, asOfUtc, windowDays, minSamples, minDays, zone, "Seasonal"));
            }
        }
        return results;
    }

    private static BaselineResult Build((string Metric, int Server, int? Database, string? Entity) key, IEnumerable<AnomalySample> source, int? dow, int? hour, DateTime asOf, int windowDays, int minSamples, int minDays, TimeZoneInfo zone, string scope)
    {
        var materialized = source.ToArray();
        var values = materialized.Select(x => x.ObservedValue).OrderBy(x => x).ToArray();
        var median = Percentile(values, .50m);
        var deviations = values.Select(x => Math.Abs(x - median)).OrderBy(x => x).ToArray();
        var mean = values.Average();
        var variance = values.Length > 1 ? values.Sum(x => Math.Pow((double)(x - mean), 2)) / (values.Length - 1) : 0;
        var historyDays = materialized.Select(x => TimeZoneInfo.ConvertTime(x.ObservedAtUtc, zone).Date).Distinct().Count();
        var status = values.Length >= minSamples && historyDays >= minDays ? "Usable" : "InsufficientData";
        return new(key.Metric, key.Server, key.Database, key.Entity, dow, hour, windowDays, values.Length, median, Percentile(values, .75m), Percentile(values, .90m), Percentile(values, .95m), Percentile(values, .99m), mean, (decimal)Math.Sqrt(variance), Percentile(deviations, .50m), values[0], values[^1], asOf, asOf.AddDays(-windowDays), status, scope);
    }

    public static decimal Percentile(IReadOnlyList<decimal> sorted, decimal percentile)
    {
        if (sorted.Count == 0) return 0;
        if (sorted.Count == 1) return sorted[0];
        var position = (sorted.Count - 1) * percentile;
        var lower = (int)Math.Floor(position); var upper = (int)Math.Ceiling(position);
        if (lower == upper) return sorted[lower];
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
    }

    private static (string Metric, int Server, int? Database, string? Entity) Key(AnomalySample x) => (x.MetricType, x.ServerId, x.DatabaseId, x.EntityKey);
    private static (int DayOfWeek, int Hour) Bucket(DateTimeOffset value, TimeZoneInfo zone) { var local = TimeZoneInfo.ConvertTime(value, zone); return ((int)local.DayOfWeek, local.Hour); }
    private static TimeZoneInfo FindTimeZone(string id) { try { return TimeZoneInfo.FindSystemTimeZoneById(id); } catch { return TimeZoneInfo.Utc; } }
}
