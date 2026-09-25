using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using DBAPulse.Data;

namespace DBAPulse.Api;

public sealed record AiSettings(string Provider, string Model, string BaseUrl, string Protocol, string ApiKey);
public sealed record AiSettingsView(string Provider, string Model, string BaseUrl, string Protocol, bool IsConfigured);
public sealed record AiSettingsUpdate(string? Provider, string? Model, string? BaseUrl, string? Protocol, string? ApiKey);
public sealed record AiSummaryResponse(bool Configured, string Provider, string Model, string Summary, string? Error);

public sealed class AiSettingsStore
{
    private readonly object _sync = new();
    private AiSettings _settings;
    public AiSettingsStore(IConfiguration configuration) => _settings = new(
        configuration["DBAPULSE_AI_PROVIDER"] ?? "none",
        configuration["DBAPULSE_AI_MODEL"] ?? "gpt-5",
        configuration["DBAPULSE_AI_BASE_URL"] ?? "https://api.openai.com",
        configuration["DBAPULSE_AI_PROTOCOL"] ?? "responses",
        configuration["DBAPULSE_AI_API_KEY"] ?? string.Empty);
    public AiSettings Current { get { lock (_sync) return _settings; } }
    public void Update(AiSettingsUpdate update)
    {
        lock (_sync) _settings = _settings with {
            Provider = string.IsNullOrWhiteSpace(update.Provider) ? _settings.Provider : update.Provider.Trim(),
            Model = string.IsNullOrWhiteSpace(update.Model) ? _settings.Model : update.Model.Trim(),
            BaseUrl = string.IsNullOrWhiteSpace(update.BaseUrl) ? _settings.BaseUrl : update.BaseUrl.Trim().TrimEnd('/'),
            Protocol = string.IsNullOrWhiteSpace(update.Protocol) ? _settings.Protocol : update.Protocol.Trim(),
            ApiKey = string.IsNullOrWhiteSpace(update.ApiKey) ? _settings.ApiKey : update.ApiKey.Trim()
        };
    }
    public AiSettingsView View() { var s = Current; return new(s.Provider, s.Model, s.BaseUrl, s.Protocol, !string.IsNullOrWhiteSpace(s.ApiKey) && !string.Equals(s.Provider, "none", StringComparison.OrdinalIgnoreCase)); }
}

public sealed class AiSummaryService
{
    private readonly HttpClient _http;
    private readonly AiSettingsStore _settings;
    private readonly DashboardStore _dashboard;
    private readonly ManagementReadStore _management;
    private readonly ILogger<AiSummaryService> _logger;
    public AiSummaryService(HttpClient http, AiSettingsStore settings, DashboardStore dashboard, ManagementReadStore management, ILogger<AiSummaryService> logger) { _http = http; _settings = settings; _dashboard = dashboard; _management = management; _logger = logger; }

    public async Task<(bool Success, string Message)> TestAsync(CancellationToken token)
    {
        var settings = _settings.Current;
        var apiKey = NormalizeApiKey(settings.ApiKey);
        if (apiKey.Any(c => c > 127)) return (false, "API key contains non-ASCII characters. Re-enter it without spaces or line breaks.");
        if (string.Equals(settings.Provider, "none", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(apiKey)) return (false, "AI provider is not configured.");
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(settings));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            object payload = string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase)
                ? new { model = settings.Model, messages = new[] { new { role = "user", content = "Reply with OK." } }, max_tokens = 8 }
                : new { model = settings.Model, input = "Reply with OK.", store = false };
            request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
            using var response = await _http.SendAsync(request, token);
            return response.IsSuccessStatusCode ? (true, "AI provider connection successful.") : ((int)response.StatusCode == 401 ? (false, "The API key was rejected by the provider.") : (false, $"Provider returned HTTP {(int)response.StatusCode}."));
        }
        catch (TaskCanceledException ex) when (!token.IsCancellationRequested) { _logger.LogWarning(ex, "AI provider test timed out for {BaseUrl}", settings.BaseUrl); return (false, "AI provider request timed out."); }
        catch (HttpRequestException ex) { _logger.LogWarning(ex, "AI provider test network/TLS error for {BaseUrl}", settings.BaseUrl); return (false, $"AI provider network/TLS error: {ex.Message}"); }
    }
    public async Task<AiSummaryResponse> SummarizeAsync(int serverId, CancellationToken token)
    {
        var settings = _settings.Current;
        var apiKey = NormalizeApiKey(settings.ApiKey);
        if (apiKey.Any(c => c > 127)) return new(true, settings.Provider, settings.Model, string.Empty, "API key contains non-ASCII characters. Re-enter it without spaces or line breaks.");
        if (string.Equals(settings.Provider, "none", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(apiKey)) return new(false, settings.Provider, settings.Model, string.Empty, "AI provider is not configured. Open Settings and add an API key.");
        var detail = await _dashboard.GetServerDetailAsync(serverId, token);
        if (detail.Server is null) return new(true, settings.Provider, settings.Model, string.Empty, "Server not found.");
        var health = await _management.HealthAsync(serverId, null, token);
        var prompt = $"You are a senior SQL Server operations assistant. Summarize the following server for an operator. Use concise Turkish with sections: Genel Durum, Riskler, Önerilen Aksiyonlar. Do not invent facts; explicitly say when data is unavailable. Server: {JsonSerializer.Serialize(detail.Server)} Databases: {JsonSerializer.Serialize(detail.Databases)} Health signals: {JsonSerializer.Serialize(health)}";
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(settings));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            object payload; if (string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase)) payload = new { model = settings.Model, messages = new[] { new { role = "user", content = prompt } }, temperature = 0.2 }; else payload = new { model = settings.Model, input = prompt, store = false };
            request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
            using var response = await _http.SendAsync(request, token);
            var body = await response.Content.ReadAsStringAsync(token);
            if (!response.IsSuccessStatusCode) return new(true, settings.Provider, settings.Model, string.Empty, $"AI request failed ({(int)response.StatusCode}).");
            using var json = JsonDocument.Parse(body);
            var text = json.RootElement.TryGetProperty("output_text", out var output) ? output.GetString() : string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase) ? ExtractChatText(json.RootElement) : ExtractText(json.RootElement);
            return new(true, settings.Provider, settings.Model, text ?? "AI response did not contain text.", null);
        }
        catch (TaskCanceledException ex) when (!token.IsCancellationRequested) { _logger.LogWarning(ex, "AI summary request timed out for {BaseUrl}", settings.BaseUrl); return new(true, settings.Provider, settings.Model, string.Empty, "AI provider request timed out."); }
        catch (HttpRequestException ex) { _logger.LogWarning(ex, "AI summary network/TLS error for {BaseUrl}", settings.BaseUrl); return new(true, settings.Provider, settings.Model, string.Empty, $"AI provider network/TLS error: {ex.Message}"); }
        catch (JsonException ex) { _logger.LogWarning(ex, "AI provider returned invalid JSON for {BaseUrl}", settings.BaseUrl); return new(true, settings.Provider, settings.Model, string.Empty, "AI provider returned an invalid response."); }
    }
    private static string NormalizeApiKey(string value) => new(value.Where(c => !char.IsWhiteSpace(c)).ToArray());
    private static string Endpoint(AiSettings settings) { var route = string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase) ? "chat/completions" : "responses"; return settings.BaseUrl.EndsWith("/v1", StringComparison.OrdinalIgnoreCase) ? $"{settings.BaseUrl}/{route}" : $"{settings.BaseUrl}/v1/{route}"; }
    private static string? ExtractChatText(JsonElement root) => root.TryGetProperty("choices", out var choices) && choices.GetArrayLength() > 0 && choices[0].TryGetProperty("message", out var message) && message.TryGetProperty("content", out var content) ? content.GetString() : null;

    private static string? ExtractText(JsonElement root)
    {
        if (!root.TryGetProperty("output", out var output) || output.ValueKind != JsonValueKind.Array) return null;
        var parts = new List<string>(); foreach (var item in output.EnumerateArray()) if (item.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array) foreach (var c in content.EnumerateArray()) if (c.TryGetProperty("text", out var text)) parts.Add(text.GetString() ?? string.Empty);
        return string.Join("\n", parts);
    }
}