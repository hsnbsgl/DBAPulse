using System.Data;
using Microsoft.Data.SqlClient;

namespace DBAPulse.Api;

public sealed record RetentionSettings(int CleanupIntervalHours);
public sealed record RetentionSettingsUpdate(int? CleanupIntervalHours);

public sealed class RetentionSettingsService
{
    private readonly string _connectionString;
    public RetentionSettingsService(IConfiguration configuration)
    {
        var connection = configuration["DBAPULSE_API_CONNECTION"] ?? throw new InvalidOperationException("DBAPULSE_API_CONNECTION is required.");
        _connectionString = new SqlConnectionStringBuilder(connection) { InitialCatalog = "DBA_PULSE" }.ConnectionString;
    }

    public async Task<RetentionSettings> GetAsync(CancellationToken token)
    {
        await using var connection = new SqlConnection(_connectionString); await connection.OpenAsync(token);
        await using var command = new SqlCommand("SELECT CleanupIntervalHours FROM dbo.RetentionSettings WHERE Id=1", connection);
        var value = await command.ExecuteScalarAsync(token);
        return new(value is null or DBNull ? 24 : Convert.ToInt32(value));
    }

    public async Task<RetentionSettings> UpdateAsync(RetentionSettingsUpdate update, CancellationToken token)
    {
        if (update.CleanupIntervalHours is < 1 or > 720) throw new ArgumentOutOfRangeException(nameof(update), "Cleanup interval must be between 1 and 720 hours.");
        await using var connection = new SqlConnection(_connectionString); await connection.OpenAsync(token);
        await using var command = new SqlCommand("UPDATE dbo.RetentionSettings SET CleanupIntervalHours=@Hours WHERE Id=1", connection);
        command.Parameters.Add("@Hours", SqlDbType.Int).Value = update.CleanupIntervalHours ?? 24;
        await command.ExecuteNonQueryAsync(token);
        return await GetAsync(token);
    }
}
