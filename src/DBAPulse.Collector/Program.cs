using DBAPulse.Collector;
using DBAPulse.Data;

var builder = Host.CreateApplicationBuilder(args);
var source = builder.Configuration["DBAPULSE_SOURCE_CONNECTION"];
var management = builder.Configuration["DBAPULSE_MANAGEMENT_CONNECTION"];
if (string.IsNullOrWhiteSpace(source) || string.IsNullOrWhiteSpace(management))
    throw new InvalidOperationException("DBAPULSE_SOURCE_CONNECTION and DBAPULSE_MANAGEMENT_CONNECTION are required.");

var options = new SqlOptions
{
    SourceConnectionString = source,
    ManagementConnectionString = management,
    DisplayTimeZone = builder.Configuration["DBAPULSE_DISPLAY_TIMEZONE"] ?? "Europe/Istanbul"
};
builder.Services.AddSingleton(options);
builder.Services.AddSingleton<ManagementStore>();
builder.Services.AddSingleton(new BaselineStore(management));
builder.Services.AddSingleton<OperationalEventCorrelator>();
builder.Services.AddSingleton<AnomalyEngine>();
builder.Services.AddSingleton(new SourceQueryClient(source, Path.Combine(AppContext.BaseDirectory, "queries")));
builder.Services.AddSingleton(sp => new MigrationRunner(options, sp.GetRequiredService<ILogger<MigrationRunner>>(), Path.Combine(AppContext.BaseDirectory, "database", "migrations")));
builder.Services.AddHostedService<CollectorWorker>();

using var host = builder.Build();
await host.Services.GetRequiredService<MigrationRunner>().ApplyAsync(CancellationToken.None);
await host.RunAsync();
