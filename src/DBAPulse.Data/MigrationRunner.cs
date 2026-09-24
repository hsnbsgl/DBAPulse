using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace DBAPulse.Data;

public sealed class MigrationRunner
{
    private readonly string _managementConnectionString;
    private readonly string _migrationDirectory;
    private readonly ILogger<MigrationRunner> _logger;

    public MigrationRunner(SqlOptions options, ILogger<MigrationRunner> logger, string migrationDirectory)
    {
        _managementConnectionString = options.ManagementConnectionString;
        _migrationDirectory = migrationDirectory;
        _logger = logger;
    }

    public async Task ApplyAsync(CancellationToken cancellationToken)
    {
        var files = Directory.GetFiles(_migrationDirectory, "V*.sql").OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToArray();
        var masterBuilder = new SqlConnectionStringBuilder(_managementConnectionString) { InitialCatalog = "master" };
        await using (var connection = new SqlConnection(masterBuilder.ConnectionString))
        {
            await connection.OpenAsync(cancellationToken);
            foreach (var batch in SplitBatches(await File.ReadAllTextAsync(files[0], cancellationToken)))
            {
                await using var command = new SqlCommand(batch, connection);
                await command.ExecuteNonQueryAsync(cancellationToken);
            }
        }

        var managementBuilder = new SqlConnectionStringBuilder(_managementConnectionString) { InitialCatalog = "DBA_PULSE" };
        await using var management = new SqlConnection(managementBuilder.ConnectionString);
        await management.OpenAsync(cancellationToken);
        var applied = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        await using (var check = new SqlCommand("SELECT Version FROM dbo.SchemaVersions;", management))
        await using (var reader = await check.ExecuteReaderAsync(cancellationToken))
            while (await reader.ReadAsync(cancellationToken)) applied.Add(reader.GetString(0));

        foreach (var file in files)
        {
            var version = Path.GetFileName(file).Split("__", 2)[0];
            var name = Path.GetFileNameWithoutExtension(file);
            if (applied.Contains(version))
            {
                _logger.LogInformation("Migration {Version} already applied", version);
                continue;
            }

            _logger.LogInformation("Applying migration {Version}", version);
            try
            {
                foreach (var batch in SplitBatches(await File.ReadAllTextAsync(file, cancellationToken)))
                {
                    await using var command = new SqlCommand(batch, management);
                    await command.ExecuteNonQueryAsync(cancellationToken);
                }
                await using var mark = new SqlCommand("INSERT dbo.SchemaVersions (Version, Name) VALUES (@version, @name);", management);
                mark.Parameters.AddWithValue("@version", version);
                mark.Parameters.AddWithValue("@name", name);
                await mark.ExecuteNonQueryAsync(cancellationToken);
                _logger.LogInformation("Migration {Version} applied", version);
            }
            catch
            {
                _logger.LogError("Migration {Version} failed; execution stopped", version);
                throw;
            }
        }
    }

    private static IEnumerable<string> SplitBatches(string script) =>
        Regex.Split(script, @"^\s*GO\s*\r?$", RegexOptions.Multiline | RegexOptions.IgnoreCase)
            .Select(x => x.Trim()).Where(x => x.Length > 0);
}
