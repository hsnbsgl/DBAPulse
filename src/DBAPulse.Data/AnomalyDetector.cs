using System.Security.Cryptography;
using System.Text;
using DBAPulse.Domain;

namespace DBAPulse.Data;

public sealed class AnomalyDetector
{
    public AnomalyEvaluation? Evaluate(AnomalySample sample, BaselineResult? baseline, AnomalyPolicy policy)
    {
        if (baseline is null || baseline.Status != "Usable" || !policy.IsEnabled || sample.ObservedValue < policy.MinObservedValue) return null;
        var modifiedZ = baseline.MadValue > 0 ? .6745m * (sample.ObservedValue - baseline.MedianValue) / baseline.MadValue : (decimal?)null;
        var exceedsP95 = sample.ObservedValue > baseline.P95Value;
        var exceedsP99 = sample.ObservedValue > baseline.P99Value;
        var z = modifiedZ ?? (baseline.P95Value > baseline.MedianValue ? (sample.ObservedValue - baseline.MedianValue) / (baseline.P95Value - baseline.MedianValue) : 0);
        if (!exceedsP95 && z < policy.WarningModifiedZ) return null;
        var severity = exceedsP99 || z >= policy.CriticalModifiedZ ? "Critical" : "Warning";
        var code = exceedsP99 ? "ABOVE_P99" : exceedsP95 ? "ABOVE_P95" : "HIGH_MAD_DEVIATION";
        var ratio = baseline.P95Value > 0 ? sample.ObservedValue / baseline.P95Value : (decimal?)null;
        return new(sample.MetricType, sample.ServerId, sample.DatabaseId, sample.EntityKey, sample.ObservedAtUtc.UtcDateTime, sample.ObservedValue, baseline.MedianValue, baseline.P95Value, baseline.P99Value, baseline.MadValue, ratio, modifiedZ, baseline.BaselineScope, baseline.SampleCount, severity, "Active", code, sample.SourceEntityId, Fingerprint(sample, baseline));
    }

    public static string Fingerprint(AnomalySample sample, BaselineResult baseline)
    {
        var value = $"{sample.MetricType}|{sample.ServerId}|{sample.DatabaseId}|{sample.EntityKey}|{baseline.BaselineScope}|{baseline.DayOfWeek}|{baseline.HourOfDay}";
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    }
}
