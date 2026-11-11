using System.Net.Security;
using System.Security.Authentication;
using System.Net.Sockets;
using System.Text;

namespace DBAPulse.Api;

public sealed record SmtpSettings(string Host, int Port, string Security, string Username, string Password, string FromEmail, string FromName);
public sealed record SmtpSettingsView(string Host, int Port, string Security, string Username, string FromEmail, string FromName, bool IsConfigured);
public sealed record SmtpSettingsUpdate(string? Host, int? Port, string? Security, string? Username, string? Password, string? FromEmail, string? FromName);

public sealed class SmtpSettingsStore
{
    private readonly object _sync = new();
    private SmtpSettings _settings;
    private readonly SettingsPersistence _persistence;
    public SmtpSettingsStore(IConfiguration configuration, SettingsPersistence persistence)
    {
        _persistence = persistence;
        _settings = persistence.Load<SmtpSettings>("smtp-settings.json") ?? new(
        configuration["DBAPULSE_SMTP_HOST"] ?? string.Empty,
        int.TryParse(configuration["DBAPULSE_SMTP_PORT"], out var port) ? port : 587,
        configuration["DBAPULSE_SMTP_SECURITY"] ?? "starttls",
        configuration["DBAPULSE_SMTP_USERNAME"] ?? string.Empty,
        configuration["DBAPULSE_SMTP_PASSWORD"] ?? string.Empty,
        configuration["DBAPULSE_SMTP_FROM_EMAIL"] ?? string.Empty,
        configuration["DBAPULSE_SMTP_FROM_NAME"] ?? "DBA Pulse");
    }
    public SmtpSettings Current { get { lock (_sync) return _settings; } }
    public void Update(SmtpSettingsUpdate update)
    {
        lock (_sync) {
            var host = string.IsNullOrWhiteSpace(update.Host) ? _settings.Host : update.Host.Trim();
            var port = update.Port is > 0 and < 65536 ? update.Port.Value : _settings.Port;
            // Never send the stored password to a new endpoint unless it is re-entered in the same request.
            var endpointChanged = !string.Equals(host, _settings.Host, StringComparison.OrdinalIgnoreCase) || port != _settings.Port;
            var password = !string.IsNullOrWhiteSpace(update.Password) ? update.Password.Trim() : endpointChanged ? string.Empty : _settings.Password;
            _settings = _settings with {
            Host = host,
            Port = port,
            Security = string.IsNullOrWhiteSpace(update.Security) ? _settings.Security : update.Security.Trim().ToLowerInvariant(),
            Username = update.Username?.Trim() ?? _settings.Username,
            Password = password,
            FromEmail = update.FromEmail?.Trim() ?? _settings.FromEmail,
            FromName = update.FromName?.Trim() ?? _settings.FromName
        }; _persistence.Save("smtp-settings.json", _settings); }
    }
    public SmtpSettingsView View() { var s = Current; return new(s.Host, s.Port, s.Security, s.Username, s.FromEmail, s.FromName, !string.IsNullOrWhiteSpace(s.Host) && !string.IsNullOrWhiteSpace(s.FromEmail)); }
}

public sealed class SmtpSettingsService
{
    private readonly SmtpSettingsStore _store;
    public SmtpSettingsService(SmtpSettingsStore store) => _store = store;
    public async Task<(bool Success, string Message)> TestAsync(CancellationToken token)
    {
        var s = _store.Current;
        if (string.IsNullOrWhiteSpace(s.Host)) return (false, "SMTP server is not configured.");
        try
        {
            using var client = new TcpClient();
            await client.ConnectAsync(s.Host, s.Port, token);
            using var stream = client.GetStream();
            if (string.Equals(s.Security, "ssl", StringComparison.OrdinalIgnoreCase))
            {
                using var ssl = new SslStream(stream, leaveInnerStreamOpen: false, (_, _, _, _) => true);
                await ssl.AuthenticateAsClientAsync(new SslClientAuthenticationOptions { TargetHost = s.Host }, token);
            }
            return (true, "SMTP server connection successful.");
        }
        catch (Exception ex) when (ex is SocketException or TimeoutException or IOException or AuthenticationException)
        { return (false, $"SMTP connection failed: {ex.Message}"); }
    }
}
