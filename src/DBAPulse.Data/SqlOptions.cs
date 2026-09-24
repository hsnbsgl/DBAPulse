namespace DBAPulse.Data;

public sealed class SqlOptions
{
    public required string SourceConnectionString { get; init; }
    public required string ManagementConnectionString { get; init; }
    public string DisplayTimeZone { get; init; } = "Europe/Istanbul";
}
