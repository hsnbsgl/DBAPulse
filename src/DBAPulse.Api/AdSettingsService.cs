using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;

namespace DBAPulse.Api;

public sealed record AdSettings(string Domain, string Host, int Port, string BaseDn, string Username, string Password, bool UseSsl, bool Enabled);
public sealed record AdSettingsView(string Domain, string Host, int Port, string BaseDn, string Username, bool UseSsl, bool Enabled, bool IsConfigured);
public sealed record AdSettingsUpdate(string? Domain, string? Host, int? Port, string? BaseDn, string? Username, string? Password, bool? UseSsl, bool? Enabled);

public sealed class AdSettingsStore
{
    private readonly object _sync = new();
    private AdSettings _settings;
    public AdSettingsStore(IConfiguration configuration) => _settings = new(
        configuration["DBAPULSE_AD_DOMAIN"] ?? string.Empty,
        configuration["DBAPULSE_AD_HOST"] ?? string.Empty,
        int.TryParse(configuration["DBAPULSE_AD_PORT"], out var port) ? port : 389,
        configuration["DBAPULSE_AD_BASE_DN"] ?? string.Empty,
        configuration["DBAPULSE_AD_USERNAME"] ?? string.Empty,
        configuration["DBAPULSE_AD_PASSWORD"] ?? string.Empty,
        bool.TryParse(configuration["DBAPULSE_AD_USE_SSL"], out var ssl) && ssl,
        bool.TryParse(configuration["DBAPULSE_AD_ENABLED"], out var enabled) && enabled);
    public AdSettings Current { get { lock (_sync) return _settings; } }
    public void Update(AdSettingsUpdate update)
    {
        lock (_sync) _settings = _settings with {
            Domain = update.Domain?.Trim() ?? _settings.Domain,
            Host = update.Host?.Trim() ?? _settings.Host,
            Port = update.Port is > 0 and < 65536 ? update.Port.Value : _settings.Port,
            BaseDn = update.BaseDn?.Trim() ?? _settings.BaseDn,
            Username = update.Username?.Trim() ?? _settings.Username,
            Password = string.IsNullOrWhiteSpace(update.Password) ? _settings.Password : update.Password.Trim(),
            UseSsl = update.UseSsl ?? _settings.UseSsl,
            Enabled = update.Enabled ?? _settings.Enabled
        };
    }
    public AdSettingsView View() { var s = Current; return new(s.Domain, s.Host, s.Port, s.BaseDn, s.Username, s.UseSsl, s.Enabled, !string.IsNullOrWhiteSpace(s.Host) && !string.IsNullOrWhiteSpace(s.BaseDn)); }
}

public sealed class AdSettingsService
{
    private readonly AdSettingsStore _store;
    public AdSettingsService(AdSettingsStore store) => _store = store;
    public async Task<(bool Success, string Message)> TestAsync(CancellationToken token)
    {
        var s = _store.Current;
        if (string.IsNullOrWhiteSpace(s.Host)) return (false, "Active Directory server is not configured.");
        try
        {
            using var client = new TcpClient();
            await client.ConnectAsync(s.Host, s.Port, token);
            if (s.UseSsl)
            {
                using var stream = client.GetStream();
                using var ssl = new SslStream(stream, leaveInnerStreamOpen: false, (_, _, _, _) => true);
                await ssl.AuthenticateAsClientAsync(new SslClientAuthenticationOptions { TargetHost = s.Host }, token);
            }
            return (true, "Active Directory server connection successful.");
        }
        catch (Exception ex) when (ex is SocketException or TimeoutException or IOException or AuthenticationException)
        { return (false, $"Active Directory connection failed: {ex.Message}"); }
    }
}