using DBAPulse.Domain;

namespace DBAPulse.Data;

public static class CapacityForecastCalculator
{
    public static CapacityDatabaseRow Apply(CapacityDatabaseRow row, IReadOnlyList<CapacityHistoryRow> history, int minimumDays = 7, int minimumSamples = 7)
    {
        var daily = history.GroupBy(x => x.CollectedAtUtc.UtcDateTime.Date).Select(g => g.OrderByDescending(x => x.CollectedAtUtc).First()).OrderBy(x => x.CollectedAtUtc).ToArray();
        if (daily.Length == 0) return row with { ForecastStatus = "InsufficientData", CapacityStatus = "InsufficientData", SampleCount = 0, HistoryDays = 0 };
        var first = daily[0].CollectedAtUtc.UtcDateTime.Date; var last = daily[^1].CollectedAtUtc.UtcDateTime.Date; var historyDays = (last - first).Days;
        var n = daily.Length;
        var ys = daily.Select(x => (double)x.TotalSizeMb).ToArray(); var xs = daily.Select(x => (x.CollectedAtUtc.UtcDateTime.Date - first).Days).Select(Convert.ToDouble).ToArray();
        var sumX = xs.Sum(); var sumY = ys.Sum(); var sumXX = xs.Sum(x => x*x); var sumYY = ys.Sum(y => y*y); var sumXY = xs.Zip(ys, (x,y) => x*y).Sum();
        var denominator = n * sumXX - sumX * sumX; var slope = Math.Abs(denominator) < double.Epsilon ? 0 : (n * sumXY - sumX * sumY) / denominator; var intercept = n == 0 ? 0 : (sumY - slope * sumX) / n;
        var mean = n == 0 ? 0 : sumY / n; var ssTot = ys.Sum(y => (y-mean)*(y-mean)); var ssReg = xs.Sum(x => Math.Pow(intercept + slope*x - mean,2)); var r2 = ssTot < double.Epsilon ? 1 : Math.Clamp(ssReg / ssTot, 0, 1);
        decimal? AtOrBefore(int days) { var reference = last.AddDays(-days); var point = daily.Where(x => x.CollectedAtUtc.UtcDateTime.Date <= reference).OrderByDescending(x => x.CollectedAtUtc).FirstOrDefault(); return point?.TotalSizeMb; }
        var growth7 = AtOrBefore(7) is { } r7 ? row.CurrentTotalSizeMb-r7 : (decimal?)null; var growth30 = AtOrBefore(30) is { } r30 ? row.CurrentTotalSizeMb-r30 : (decimal?)null; var growth90 = AtOrBefore(90) is { } r90 ? row.CurrentTotalSizeMb-r90 : (decimal?)null;
        var insufficient = n < minimumSamples || historyDays < minimumDays; var status = insufficient ? "InsufficientData" : slope < -0.01 ? "StableOrShrinking" : Math.Abs(slope) <= 0.01 ? "Stable" : r2 < 0.5 ? "LowFit" : "Usable";
        var forecast30 = status is "Usable" or "LowFit" ? (decimal?)(intercept + slope * (historyDays + 30)) : null; var forecast90 = status is "Usable" or "LowFit" ? (decimal?)(intercept + slope * (historyDays + 90)) : null;
        return row with { Growth7dMb = insufficient ? null : growth7, Growth30dMb = insufficient ? null : growth30, Growth90dMb = insufficient ? null : growth90, GrowthRateMbPerDay = insufficient ? null : (decimal)slope, Forecast30dMb = forecast30, Forecast90dMb = forecast90, RSquared = insufficient ? null : (decimal)r2, SampleCount = n, HistoryDays = historyDays, ForecastStatus = status, CapacityStatus = status == "InsufficientData" ? "InsufficientData" : "Healthy" };
    }
}
