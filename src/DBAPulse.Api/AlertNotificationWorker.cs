using System.Net;
using System.Net.Mail;
using Microsoft.Data.SqlClient;

namespace DBAPulse.Api;

public sealed class AlertNotificationWorker : BackgroundService
{
    private sealed record AlertRow(long Id, string EventType, string ServerName, string? DatabaseName, string Severity, string Title, string Summary, DateTime StartedAtUtc, DateTime LastSeenAtUtc, string[] Recipients, string[] EventTypes, string[] Severities);

    private readonly string _connectionString;
    private readonly SmtpSettingsStore _smtp;
    private readonly ILogger<AlertNotificationWorker> _logger;
    private readonly bool _enabled;
    private readonly int _pollSeconds;
    private readonly string[] _recipients;

    public AlertNotificationWorker(IConfiguration configuration, SmtpSettingsStore smtp, ILogger<AlertNotificationWorker> logger)
    {
        _connectionString = new SqlConnectionStringBuilder(configuration["DBAPULSE_API_CONNECTION"] ?? string.Empty) { InitialCatalog = "DBA_PULSE" }.ConnectionString;
        _smtp = smtp;
        _logger = logger;
        _enabled = !string.Equals(configuration["DBAPULSE_ALERT_ENABLED"], "false", StringComparison.OrdinalIgnoreCase);
        _pollSeconds = int.TryParse(configuration["DBAPULSE_ALERT_POLL_SECONDS"], out var seconds) ? Math.Clamp(seconds, 10, 3600) : 30;
        _recipients = (configuration["DBAPULSE_ALERT_RECIPIENTS"] ?? string.Empty)
            .Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_enabled)
        {
            _logger.LogInformation("Alert notifications disabled or no recipients configured.");
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try { await ProcessAsync(stoppingToken); }
            catch (Exception exception) { _logger.LogError(exception, "Alert notification scan failed"); }
            await Task.Delay(TimeSpan.FromSeconds(_pollSeconds), stoppingToken);
        }
    }

    private async Task ProcessAsync(CancellationToken token)
    {
        var alerts = await ReadPendingAlertsAsync(token);
        foreach (var alert in alerts)
        {
            try
            {
                await SendAsync(alert, token);
                await MarkDeliveredAsync(alert, token);
                _logger.LogInformation("Alert notification sent for operational event {EventId}", alert.Id);
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Alert notification failed for operational event {EventId}", alert.Id);
            }
        }
    }

    private async Task<IReadOnlyList<AlertRow>> ReadPendingAlertsAsync(CancellationToken token)
    {
        const string sql = """
            SELECT TOP (50) e.Id,e.EventType,s.ServerName,d.DatabaseName,e.Severity,e.Title,e.Summary,e.StartedAtUtc,e.LastSeenAtUtc,ISNULL(s.AlertRecipients,N'') AS AlertRecipients,ISNULL(s.AlertEventTypes,N'') AS AlertEventTypes,ISNULL(s.AlertSeverities,N'') AS AlertSeverities
            FROM dbo.OperationalEvents e
            INNER JOIN dbo.Servers s ON s.Id=e.ServerId
            LEFT JOIN dbo.Databases d ON d.Id=e.DatabaseId
            WHERE e.Status=N'Active'
              AND e.Severity IN (N'Warning',N'Critical')
              AND NOT EXISTS (SELECT 1 FROM dbo.AlertNotificationDeliveries n WHERE n.OperationalEventId=e.Id)
            ORDER BY CASE WHEN e.Severity=N'Critical' THEN 0 ELSE 1 END,e.StartedAtUtc;
            """;
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand(sql, connection) { CommandTimeout = 30 };
        await using var reader = await command.ExecuteReaderAsync(token);
        var rows = new List<AlertRow>();
        while (await reader.ReadAsync(token))
        {
            rows.Add(new(
                Convert.ToInt64(reader["Id"]), Convert.ToString(reader["EventType"]) ?? string.Empty,
                Convert.ToString(reader["ServerName"]) ?? string.Empty,
                reader.IsDBNull(reader.GetOrdinal("DatabaseName")) ? null : Convert.ToString(reader["DatabaseName"]),
                Convert.ToString(reader["Severity"]) ?? string.Empty, Convert.ToString(reader["Title"]) ?? string.Empty,
                Convert.ToString(reader["Summary"]) ?? string.Empty, Convert.ToDateTime(reader["StartedAtUtc"]), Convert.ToDateTime(reader["LastSeenAtUtc"]),
                ParseList(Convert.ToString(reader["AlertRecipients"]) ?? string.Empty),
                ParseList(Convert.ToString(reader["AlertEventTypes"]) ?? string.Empty),
                ParseList(Convert.ToString(reader["AlertSeverities"]) ?? string.Empty)));
        }
        return rows.Where(alert => alert.EventTypes.Contains(alert.EventType, StringComparer.OrdinalIgnoreCase)
                                 && alert.Severities.Contains(alert.Severity, StringComparer.OrdinalIgnoreCase)).ToArray();
    }

    private async Task SendAsync(AlertRow alert, CancellationToken token)
    {
        var settings = _smtp.Current;
        var recipients = alert.Recipients.Length > 0 ? alert.Recipients : _recipients;
        if (recipients.Length == 0) throw new InvalidOperationException($"No alert recipients are configured for server {alert.ServerName}.");
        if (string.IsNullOrWhiteSpace(settings.Host)) throw new InvalidOperationException("SMTP server is not configured.");
        using var message = new MailMessage
        {
            From = new MailAddress(string.IsNullOrWhiteSpace(settings.FromEmail) ? "dbapulse@localhost" : settings.FromEmail, settings.FromName),
            Subject = $"[DBA Pulse][{alert.Severity}] {alert.Title}",
            Body = $"DBA Pulse alarm\n\nSeverity: {alert.Severity}\nEvent: {alert.EventType}\nServer: {alert.ServerName}\nDatabase: {alert.DatabaseName ?? "N/A"}\nStarted: {alert.StartedAtUtc:O}\nLast seen: {alert.LastSeenAtUtc:O}\n\n{alert.Summary}",
            IsBodyHtml = false
        };
        foreach (var recipient in recipients) message.To.Add(recipient);
        using var client = new SmtpClient(settings.Host, settings.Port)
        {
            EnableSsl = !string.Equals(settings.Security, "none", StringComparison.OrdinalIgnoreCase),
            DeliveryMethod = SmtpDeliveryMethod.Network,
            UseDefaultCredentials = false
        };
        if (!string.IsNullOrWhiteSpace(settings.Username)) client.Credentials = new NetworkCredential(settings.Username, settings.Password);
        await client.SendMailAsync(message, token);
    }

    private async Task MarkDeliveredAsync(AlertRow alert, CancellationToken token)
    {
        const string sql = "INSERT INTO dbo.AlertNotificationDeliveries(OperationalEventId,Severity,RecipientList) VALUES(@Id,@Severity,@Recipients);";
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(token);
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.AddWithValue("@Id", alert.Id);
        command.Parameters.AddWithValue("@Severity", alert.Severity);
        command.Parameters.AddWithValue("@Recipients", string.Join(",", alert.Recipients.Length > 0 ? alert.Recipients : _recipients));
        await command.ExecuteNonQueryAsync(token);
    }

    private static string[] ParseList(string value) => value
        .Split(new[] { ',', ';', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .ToArray();
}
