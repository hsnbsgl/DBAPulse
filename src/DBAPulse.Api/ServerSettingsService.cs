using System.Data;
using Microsoft.Data.SqlClient;

namespace DBAPulse.Api;

public sealed record ServerSetting(int ServerId, string ServerName, string InstanceName, string SqlVersion, string Edition, string Environment, bool IsActive, int CollectionIntervalMinutes, int CapacityIntervalMinutes, DateTime LastSeenAtUtc);
public sealed record ServerSettingsUpdate(bool? IsActive, int? CollectionIntervalMinutes, int? CapacityIntervalMinutes, string? Environment);
public sealed record BackupScopeSetting(int DatabaseId, int ServerId, string ServerName, string DatabaseName, string DatabaseStatus, string RecoveryModel, string BackupProtectionMode, bool IsMirrored, string Environment);
public sealed record BackupScopeUpdate(string Mode);

public sealed class ServerSettingsService
{
    private readonly string _connectionString;
    public ServerSettingsService(IConfiguration configuration)
    {
        var connection = configuration["DBAPULSE_API_CONNECTION"] ?? throw new InvalidOperationException("DBAPULSE_API_CONNECTION is required.");
        _connectionString = new SqlConnectionStringBuilder(connection) { InitialCatalog = "DBA_PULSE" }.ConnectionString;
    }
    public async Task<IReadOnlyList<ServerSetting>> ListAsync(CancellationToken token)
    {
        const string sql = "SELECT Id,ServerName,InstanceName,SqlVersion,Edition,Environment,IsActive,CollectionIntervalMinutes,CapacityIntervalMinutes,LastSeenAtUtc FROM dbo.Servers ORDER BY ServerName";
        await using var connection = new SqlConnection(_connectionString); await connection.OpenAsync(token);
        await using var command = new SqlCommand(sql, connection); await using var reader = await command.ExecuteReaderAsync(token);
        var result = new List<ServerSetting>();
        while (await reader.ReadAsync(token)) result.Add(new(reader.GetInt32(0), reader.GetString(1), reader.GetString(2), reader.GetString(3), reader.GetString(4), reader.GetString(5), reader.GetBoolean(6), reader.GetInt32(7), reader.GetInt32(8), reader.GetDateTime(9)));
        return result;
    }
    public async Task<bool> UpdateAsync(int id, ServerSettingsUpdate update, CancellationToken token)
    {
        if (update.IsActive is null && update.CollectionIntervalMinutes is null && update.CapacityIntervalMinutes is null && update.Environment is null) return false;
        if (update.CollectionIntervalMinutes is < 1 or > 1440 || update.CapacityIntervalMinutes is < 1 or > 1440) throw new ArgumentOutOfRangeException(nameof(update), "Intervals must be between 1 and 1440 minutes.");
        var environment = update.Environment is null ? null : NormalizeEnvironment(update.Environment);
        await using var connection = new SqlConnection(_connectionString); await connection.OpenAsync(token);
        await using var transaction = await connection.BeginTransactionAsync(token);
        const string sql = "UPDATE dbo.Servers SET IsActive=COALESCE(@IsActive,IsActive), CollectionIntervalMinutes=COALESCE(@CollectionIntervalMinutes,CollectionIntervalMinutes), CapacityIntervalMinutes=COALESCE(@CapacityIntervalMinutes,CapacityIntervalMinutes), Environment=COALESCE(@Environment,Environment) WHERE Id=@Id";
        await using var command = new SqlCommand(sql, connection, (SqlTransaction)transaction);
        command.Parameters.Add("@IsActive", SqlDbType.Bit).Value = (object?)update.IsActive ?? DBNull.Value;
        command.Parameters.Add("@CollectionIntervalMinutes", SqlDbType.Int).Value = (object?)update.CollectionIntervalMinutes ?? DBNull.Value;
        command.Parameters.Add("@CapacityIntervalMinutes", SqlDbType.Int).Value = (object?)update.CapacityIntervalMinutes ?? DBNull.Value;
        command.Parameters.Add("@Environment", SqlDbType.NVarChar, 20).Value = (object?)environment ?? DBNull.Value;
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
        var changed = await command.ExecuteNonQueryAsync(token);
        if (changed > 0 && update.IsActive.HasValue)
        {
            await using var databases = new SqlCommand("UPDATE dbo.Databases SET IsActive=@IsActive WHERE ServerId=@Id", connection, (SqlTransaction)transaction);
            databases.Parameters.Add("@IsActive", SqlDbType.Bit).Value = update.IsActive.Value; databases.Parameters.Add("@Id", SqlDbType.Int).Value = id;
            await databases.ExecuteNonQueryAsync(token);
        }
        await transaction.CommitAsync(token);
        return changed > 0;
    }

    public async Task<IReadOnlyList<BackupScopeSetting>> ListBackupScopeAsync(int? serverId, CancellationToken token)
    {
        const string sql = "SELECT d.Id,d.ServerId,s.ServerName,d.DatabaseName,d.DatabaseStatus,d.RecoveryModel,d.BackupProtectionMode,d.IsMirrored,s.Environment FROM dbo.Databases d INNER JOIN dbo.Servers s ON s.Id=d.ServerId WHERE d.IsActive=1 AND s.IsActive=1 AND (@ServerId IS NULL OR d.ServerId=@ServerId) ORDER BY s.ServerName,d.DatabaseName";
        await using var connection = new SqlConnection(_connectionString); await connection.OpenAsync(token);
        await using var command = new SqlCommand(sql, connection); command.Parameters.Add("@ServerId", SqlDbType.Int).Value = (object?)serverId ?? DBNull.Value;
        await using var reader = await command.ExecuteReaderAsync(token); var result = new List<BackupScopeSetting>();
        while (await reader.ReadAsync(token)) result.Add(new(reader.GetInt32(0), reader.GetInt32(1), reader.GetString(2), reader.GetString(3), reader.GetString(4), reader.GetString(5), reader.GetString(6), reader.GetBoolean(7), reader.GetString(8)));
        return result;
    }

    public async Task<bool> UpdateBackupScopeAsync(int databaseId, BackupScopeUpdate update, CancellationToken token)
    {
        var mode = NormalizeBackupMode(update.Mode);
        await using var connection = new SqlConnection(_connectionString); await connection.OpenAsync(token);
        await using var command = new SqlCommand("UPDATE dbo.Databases SET BackupProtectionMode=@Mode WHERE Id=@DatabaseId", connection);
        command.Parameters.Add("@Mode", SqlDbType.NVarChar, 20).Value = mode; command.Parameters.Add("@DatabaseId", SqlDbType.Int).Value = databaseId;
        return await command.ExecuteNonQueryAsync(token) > 0;
    }

    public async Task<(int CollectionIntervalMinutes, int CapacityIntervalMinutes)> GetIntervalsAsync(int id, CancellationToken token)
    {
        await using var connection = new SqlConnection(_connectionString); await connection.OpenAsync(token);
        await using var command = new SqlCommand("SELECT CollectionIntervalMinutes,CapacityIntervalMinutes FROM dbo.Servers WHERE Id=@Id", connection);
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
        await using var reader = await command.ExecuteReaderAsync(token);
        return await reader.ReadAsync(token) ? (reader.GetInt32(0), reader.GetInt32(1)) : (5, 60);
    }

    private static string NormalizeEnvironment(string value) => value.Trim().ToUpperInvariant() switch
    {
        "DEV" => "Dev",
        "TEST" => "Test",
        "STAGE" => "Stage",
        "PROD" => "Prod",
        _ => throw new ArgumentOutOfRangeException(nameof(value), "Environment must be Dev, Test, Stage or Prod.")
    };

    private static string NormalizeBackupMode(string value) => value.Trim().ToUpperInvariant() switch
    {
        "AUTO" => "Auto",
        "REQUIRED" => "Required",
        "EXCLUDED" => "Excluded",
        _ => throw new ArgumentOutOfRangeException(nameof(value), "Backup mode must be Auto, Required or Excluded.")
    };
}
