using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace DBAPulse.Data;

public sealed class MigrationRunner
{
    private const string LockResource = "DBAPulse.Migrations";
    private const int MigrationCommandTimeoutSeconds = 3600;
    private const int LockTimeoutMilliseconds = 30 * 60 * 1000;
    private const int ConnectAttempts = 6;
    private static readonly Regex NonTransactionalStatement = new(@"\b(CREATE|ALTER|DROP)\s+DATABASE\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
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
        var files = (Directory.Exists(_migrationDirectory) ? Directory.GetFiles(_migrationDirectory, "V*.sql") : Array.Empty<string>())
            .Select(x => (Path: x, Version: Path.GetFileName(x).Split("__", 2)[0]))
            .OrderBy(x => VersionNumber(x.Version)).ThenBy(x => x.Version, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        if (files.Length == 0)
        {
            _logger.LogWarning("No migration files found in {Directory}; skipping schema migration", _migrationDirectory);
            return;
        }

        var masterBuilder = new SqlConnectionStringBuilder(_managementConnectionString) { InitialCatalog = "master" };
        // Dedicated, non-pooled connection that owns the session-level applock for the whole run, so concurrent
        // collectors cannot apply the same migration; closing it physically always releases the lock.
        var lockBuilder = new SqlConnectionStringBuilder(masterBuilder.ConnectionString) { Pooling = false };
        await using var lockConnection = await OpenWithRetryAsync(lockBuilder.ConnectionString, cancellationToken);
        await AcquireLockAsync(lockConnection, cancellationToken);
        try
        {
            await using (var connection = await OpenWithRetryAsync(masterBuilder.ConnectionString, cancellationToken))
            {
                foreach (var batch in SplitBatches(await File.ReadAllTextAsync(files[0].Path, cancellationToken)))
                {
                    await using var command = new SqlCommand(batch, connection) { CommandTimeout = MigrationCommandTimeoutSeconds };
                    await command.ExecuteNonQueryAsync(cancellationToken);
                }
            }

            var managementBuilder = new SqlConnectionStringBuilder(_managementConnectionString) { InitialCatalog = "DBA_PULSE" };
            await using var management = await OpenWithRetryAsync(managementBuilder.ConnectionString, cancellationToken);
            var applied = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            await using (var check = new SqlCommand("SELECT Version FROM dbo.SchemaVersions;", management))
            await using (var reader = await check.ExecuteReaderAsync(cancellationToken))
                while (await reader.ReadAsync(cancellationToken)) applied.Add(reader.GetString(0));

            foreach (var (file, version) in files)
            {
                var name = Path.GetFileNameWithoutExtension(file);
                if (applied.Contains(version))
                {
                    _logger.LogInformation("Migration {Version} already applied", version);
                    continue;
                }

                _logger.LogInformation("Applying migration {Version}", version);
                var script = await File.ReadAllTextAsync(file, cancellationToken);
                // Batches + version row commit atomically; database-level DDL cannot run inside a user transaction.
                SqlTransaction? transaction = NonTransactionalStatement.IsMatch(script) ? null : management.BeginTransaction();
                try
                {
                    foreach (var batch in SplitBatches(script))
                    {
                        await using var command = new SqlCommand(batch, management, transaction) { CommandTimeout = MigrationCommandTimeoutSeconds };
                        await command.ExecuteNonQueryAsync(cancellationToken);
                    }
                    await using (var mark = new SqlCommand("INSERT dbo.SchemaVersions (Version, Name) VALUES (@version, @name);", management, transaction))
                    {
                        mark.Parameters.AddWithValue("@version", version);
                        mark.Parameters.AddWithValue("@name", name);
                        await mark.ExecuteNonQueryAsync(cancellationToken);
                    }
                    if (transaction is not null) await transaction.CommitAsync(cancellationToken);
                    _logger.LogInformation("Migration {Version} applied", version);
                }
                catch (Exception ex)
                {
                    if (transaction is not null)
                    {
                        try { await transaction.RollbackAsync(CancellationToken.None); }
                        catch (Exception rollbackError) { _logger.LogWarning(rollbackError, "Rollback of migration {Version} failed", version); }
                    }
                    _logger.LogError(ex, "Migration {Version} failed; execution stopped", version);
                    throw;
                }
                finally
                {
                    if (transaction is not null) await transaction.DisposeAsync();
                }
            }
        }
        finally
        {
            try
            {
                await using var release = new SqlCommand("EXEC sp_releaseapplock @Resource = @resource, @LockOwner = N'Session';", lockConnection);
                release.Parameters.AddWithValue("@resource", LockResource);
                await release.ExecuteNonQueryAsync(CancellationToken.None);
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Could not release migration lock explicitly; it is released when the connection closes"); }
        }
    }

    private async Task AcquireLockAsync(SqlConnection connection, CancellationToken cancellationToken)
    {
        await using var command = new SqlCommand("DECLARE @result int; EXEC @result = sp_getapplock @Resource = @resource, @LockMode = N'Exclusive', @LockOwner = N'Session', @LockTimeout = @timeout; SELECT @result;", connection) { CommandTimeout = 0 };
        command.Parameters.AddWithValue("@resource", LockResource);
        command.Parameters.AddWithValue("@timeout", LockTimeoutMilliseconds);
        _logger.LogInformation("Waiting for migration lock {Resource}", LockResource);
        var result = Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
        if (result < 0) throw new InvalidOperationException($"Could not acquire migration lock {LockResource} (sp_getapplock returned {result}).");
        _logger.LogInformation("Migration lock acquired");
    }

    private async Task<SqlConnection> OpenWithRetryAsync(string connectionString, CancellationToken cancellationToken)
    {
        for (var attempt = 1; ; attempt++)
        {
            var connection = new SqlConnection(connectionString);
            try
            {
                await connection.OpenAsync(cancellationToken);
                return connection;
            }
            catch (SqlException ex) when (attempt < ConnectAttempts)
            {
                await connection.DisposeAsync();
                var delay = TimeSpan.FromSeconds(5 * attempt);
                _logger.LogWarning(ex, "Management SQL Server connection attempt {Attempt}/{Attempts} failed; retrying in {DelaySeconds} s", attempt, ConnectAttempts, delay.TotalSeconds);
                await Task.Delay(delay, cancellationToken);
            }
            catch
            {
                await connection.DisposeAsync();
                throw;
            }
        }
    }

    // "V064" -> 64; numeric ordering so V1000 sorts after V999. Unparseable versions sort last.
    private static long VersionNumber(string version)
    {
        var digits = new string(version.TrimStart('V', 'v').TakeWhile(char.IsDigit).ToArray());
        return long.TryParse(digits, out var value) ? value : long.MaxValue;
    }

    private static IEnumerable<string> SplitBatches(string script) =>
        Regex.Split(script, @"^\s*GO\s*\r?$", RegexOptions.Multiline | RegexOptions.IgnoreCase)
            .Select(x => x.Trim()).Where(x => x.Length > 0);
}
