using System.Text.Json;

namespace DBAPulse.Api;

public sealed class SettingsPersistence
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private readonly string _directory;

    public SettingsPersistence(IConfiguration configuration)
    {
        _directory = configuration["DBAPULSE_SETTINGS_DIRECTORY"] ?? Path.Combine(AppContext.BaseDirectory, "data");
    }

    public T? Load<T>(string name)
    {
        var path = Path.Combine(_directory, name);
        if (!File.Exists(path)) return default;
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions); }
        catch (JsonException) { return default; }
    }

    public void Save<T>(string name, T value)
    {
        Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, name);
        var temporaryPath = path + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(value, JsonOptions));
        File.Move(temporaryPath, path, true);
    }
}
