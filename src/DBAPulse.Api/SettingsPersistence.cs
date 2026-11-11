using System.Text.Json;

namespace DBAPulse.Api;

public sealed class SettingsPersistence
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private const UnixFileMode OwnerOnly = UnixFileMode.UserRead | UnixFileMode.UserWrite;
    private readonly string _directory;
    private readonly ILogger<SettingsPersistence> _logger;

    public SettingsPersistence(IConfiguration configuration, ILogger<SettingsPersistence> logger)
    {
        _directory = configuration["DBAPULSE_SETTINGS_DIRECTORY"] ?? Path.Combine(AppContext.BaseDirectory, "data");
        _logger = logger;
    }

    public T? Load<T>(string name)
    {
        var path = Path.Combine(_directory, name);
        try
        {
            if (!File.Exists(path)) return default;
            return JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions);
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            _logger.LogError(ex, "Could not load settings file {SettingsFile}; falling back to defaults/environment.", path);
            return default;
        }
    }

    public void Save<T>(string name, T value)
    {
        Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, name);
        var temporaryPath = path + ".tmp";
        var options = new FileStreamOptions { Mode = FileMode.Create, Access = FileAccess.Write, Share = FileShare.None };
        if (!OperatingSystem.IsWindows()) options.UnixCreateMode = OwnerOnly;
        using (var stream = new FileStream(temporaryPath, options))
        using (var writer = new StreamWriter(stream))
        {
            writer.Write(JsonSerializer.Serialize(value, JsonOptions));
        }
        // UnixCreateMode only applies when the file is newly created; enforce it for a leftover .tmp too.
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(temporaryPath, OwnerOnly);
        File.Move(temporaryPath, path, true);
    }
}
