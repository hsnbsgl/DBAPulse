using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using DBAPulse.Data;
using DBAPulse.Domain;

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
        configuration["DBAPULSE_AI_PROVIDER"] ?? "gemini",
        configuration["DBAPULSE_AI_MODEL"] ?? "gemini-flash-latest",
        configuration["DBAPULSE_AI_BASE_URL"] ?? "https://generativelanguage.googleapis.com/v1beta",
        configuration["DBAPULSE_AI_PROTOCOL"] ?? "gemini",
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
            if (IsGemini(settings)) request.Headers.TryAddWithoutValidation("x-goog-api-key", apiKey); else request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            object payload = IsGemini(settings)
                ? new { contents = new[] { new { parts = new[] { new { text = "Reply with OK." } } } }, generationConfig = new { maxOutputTokens = 8 } }
                : string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase)
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
        var environment = await _management.ServerEnvironmentAsync(serverId, token);
        var prompt = BuildPrompt(environment, detail, health);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(settings));
            if (IsGemini(settings)) request.Headers.TryAddWithoutValidation("x-goog-api-key", apiKey); else request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            object payload = IsGemini(settings)
                ? new { contents = new[] { new { parts = new[] { new { text = prompt } } } }, generationConfig = new { temperature = 0.2 } }
                : string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase)
                    ? new { model = settings.Model, messages = new[] { new { role = "user", content = prompt } }, temperature = 0.2 }
                    : new { model = settings.Model, input = prompt, store = false };
            request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
            using var response = await _http.SendAsync(request, token);
            var body = await response.Content.ReadAsStringAsync(token);
            if (!response.IsSuccessStatusCode) return new(true, settings.Provider, settings.Model, string.Empty, $"AI request failed ({(int)response.StatusCode}).");
            using var json = JsonDocument.Parse(body);
            var text = IsGemini(settings) ? ExtractGeminiText(json.RootElement) : json.RootElement.TryGetProperty("output_text", out var output) ? output.GetString() : string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase) ? ExtractChatText(json.RootElement) : ExtractText(json.RootElement);
            return new(true, settings.Provider, settings.Model, text ?? "AI response did not contain text.", null);
        }
        catch (TaskCanceledException ex) when (!token.IsCancellationRequested) { _logger.LogWarning(ex, "AI summary request timed out for {BaseUrl}", settings.BaseUrl); return new(true, settings.Provider, settings.Model, string.Empty, "AI provider request timed out."); }
        catch (HttpRequestException ex) { _logger.LogWarning(ex, "AI summary network/TLS error for {BaseUrl}", settings.BaseUrl); return new(true, settings.Provider, settings.Model, string.Empty, $"AI provider network/TLS error: {ex.Message}"); }
        catch (JsonException ex) { _logger.LogWarning(ex, "AI provider returned invalid JSON for {BaseUrl}", settings.BaseUrl); return new(true, settings.Provider, settings.Model, string.Empty, "AI provider returned an invalid response."); }
    }
    public async Task StreamSummarizeAsync(int serverId, Stream output, CancellationToken token)
    {
        var settings = _settings.Current;
        var apiKey = NormalizeApiKey(settings.ApiKey);
        if (apiKey.Any(c => c > 127)) { await WriteEventAsync(output, "error", "API key contains non-ASCII characters. Re-enter it without spaces or line breaks.", token); return; }
        if (string.Equals(settings.Provider, "none", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(apiKey)) { await WriteEventAsync(output, "error", "AI provider is not configured. Open Settings and add an API key.", token); return; }
        var detail = await _dashboard.GetServerDetailAsync(serverId, token);
        if (detail.Server is null) { await WriteEventAsync(output, "error", "Server not found.", token); return; }
        var health = await _management.HealthAsync(serverId, null, token);
        var environment = await _management.ServerEnvironmentAsync(serverId, token);
        var prompt = BuildPrompt(environment, detail, health);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(settings, true));
            if (IsGemini(settings)) request.Headers.TryAddWithoutValidation("x-goog-api-key", apiKey); else request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            object payload = IsGemini(settings)
                ? new { contents = new[] { new { parts = new[] { new { text = prompt } } } }, generationConfig = new { temperature = 0.2 } }
                : string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase)
                    ? new { model = settings.Model, messages = new[] { new { role = "user", content = prompt } }, temperature = 0.2, stream = true }
                    : new { model = settings.Model, input = prompt, store = false, stream = true };
            request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (!response.IsSuccessStatusCode) { await WriteEventAsync(output, "error", $"AI request failed ({(int)response.StatusCode}).", token); return; }
            await using var body = await response.Content.ReadAsStreamAsync(token);
            using var reader = new StreamReader(body);
            while (await reader.ReadLineAsync(token) is { } line)
            {
                if (!line.StartsWith("data:", StringComparison.OrdinalIgnoreCase)) continue;
                var data = line[5..].Trim();
                if (data == "[DONE]") break;
                try
                {
                    using var json = JsonDocument.Parse(data);
                    var text = ExtractStreamText(json.RootElement, settings.Protocol);
                    if (!string.IsNullOrEmpty(text))
                        await WriteEventAsync(output, "token", text, token);
                }
                catch (JsonException) { /* Ignore provider keep-alive or non-JSON SSE frames. */ }
            }
            await WriteEventAsync(output, "done", string.Empty, token);
        }
        catch (TaskCanceledException) when (!token.IsCancellationRequested) { _logger.LogWarning("AI summary stream timed out for {BaseUrl}", settings.BaseUrl); await WriteEventAsync(output, "error", "AI provider request timed out.", CancellationToken.None); }
        catch (HttpRequestException ex) { _logger.LogWarning(ex, "AI summary stream network/TLS error for {BaseUrl}", settings.BaseUrl); await WriteEventAsync(output, "error", $"AI provider network/TLS error: {ex.Message}", token); }
    }

    private static async Task WriteEventAsync(Stream output, string eventName, string data, CancellationToken token)
    {
        var payload = $"event: {eventName}\ndata: {JsonSerializer.Serialize(data)}\n\n";
        await output.WriteAsync(Encoding.UTF8.GetBytes(payload), token);
        await output.FlushAsync(token);
    }

    private static string BuildPrompt(string environment, ServerDetailResult detail, IReadOnlyList<ManagementHealthRow> health)
    {
        var profile = environment.Trim().ToUpperInvariant() switch
        {
            "PROD" => (Name: "Production operations", Focus: "Önceliği availability, backup protection, blocking/deadlock, kapasite riski ve kullanıcı etkisine ver. Critical ve Warning durumlarını en başta belirt; aksiyonları güvenli, geri dönüşlü ve read-only gözlem sınırında öner."),
            "STAGE" => (Name: "Pre-production readiness", Focus: "Önceliği production'a geçiş hazırlığına, production-benzeri workload risklerine, backup kapsamına, availability, job health, kapasite ve release öncesi açık noktalara ver."),
            "TEST" => (Name: "Test and regression analysis", Focus: "Önceliği test sonucu güvenilirliğine, tekrar eden job/backup/performance sorunlarına, regression sinyallerine ve test verisinin beklenen davranıştan sapmasına ver. Non-production gürültüsünü production incident gibi sunma."),
            "DEV" => (Name: "Development environment analysis", Focus: "Önceliği geliştirme kaynaklı blocking, başarısız job, veri/telemetry eksikliği, kapasite trendi ve geliştiricinin doğrulayabileceği teknik sorunlara ver. Development ortamı için production SLA veya incident iddiası üretme."),
            _ => (Name: "General SQL Server operations", Focus: "Ortam bilinmiyorsa gözlenen telemetry'yi tarafsız biçimde özetle; ortam varsayımı veya business SLA üretme.")
        };

        return $"You are a senior SQL Server operations assistant. Analyze the server according to its environment. Environment: {environment}. Analysis profile: {profile.Name}. {profile.Focus} Use Turkish with sections: Genel Durum, Riskler, Önerilen Aksiyonlar. Do not invent facts; explicitly say when data is unavailable, stale or insufficient. Separate observed facts from recommendations. Do not recommend destructive or automatic actions such as KILL, failover, backup start, configuration change or data deletion. Provide a sufficiently detailed response based only on the available data. Server: {JsonSerializer.Serialize(detail.Server)} Databases: {JsonSerializer.Serialize(detail.Databases)} Health signals: {JsonSerializer.Serialize(health)}";
    }

    private static string? ExtractStreamText(JsonElement root, string protocol)
    {
        if (IsGeminiProtocol(protocol)) return ExtractGeminiText(root);
        if (string.Equals(protocol, "chat-completions", StringComparison.OrdinalIgnoreCase))
        {
            return root.TryGetProperty("choices", out var choices) && choices.GetArrayLength() > 0 && choices[0].TryGetProperty("delta", out var delta) && delta.TryGetProperty("content", out var content) ? content.GetString() : null;
        }
        return root.TryGetProperty("delta", out var responseDelta) && responseDelta.ValueKind == JsonValueKind.String ? responseDelta.GetString() : null;
    }
    private static string NormalizeApiKey(string value) => new(value.Where(c => !char.IsWhiteSpace(c)).ToArray());
    private static bool IsGemini(AiSettings settings) => string.Equals(settings.Provider, "gemini", StringComparison.OrdinalIgnoreCase) || string.Equals(settings.Protocol, "gemini", StringComparison.OrdinalIgnoreCase);
    private static bool IsGeminiProtocol(string protocol) => string.Equals(protocol, "gemini", StringComparison.OrdinalIgnoreCase);
    private static string Endpoint(AiSettings settings, bool streaming = false)
    {
        if (IsGemini(settings))
        {
            var route = streaming ? "streamGenerateContent?alt=sse" : "generateContent";
            return $"{settings.BaseUrl.TrimEnd('/')}/models/{Uri.EscapeDataString(settings.Model)}:{route}";
        }
        var openAiRoute = string.Equals(settings.Protocol, "chat-completions", StringComparison.OrdinalIgnoreCase) ? "chat/completions" : "responses";
        return settings.BaseUrl.EndsWith("/v1", StringComparison.OrdinalIgnoreCase) ? $"{settings.BaseUrl}/{openAiRoute}" : $"{settings.BaseUrl}/v1/{openAiRoute}";
    }
    private static string? ExtractGeminiText(JsonElement root)
    {
        if (!root.TryGetProperty("candidates", out var candidates) || candidates.GetArrayLength() == 0) return null;
        var candidate = candidates[0];
        if (!candidate.TryGetProperty("content", out var content) || !content.TryGetProperty("parts", out var parts)) return null;
        var text = new StringBuilder();
        foreach (var part in parts.EnumerateArray()) if (part.TryGetProperty("text", out var value)) text.Append(value.GetString());
        return text.ToString();
    }    private static string? ExtractChatText(JsonElement root) => root.TryGetProperty("choices", out var choices) && choices.GetArrayLength() > 0 && choices[0].TryGetProperty("message", out var message) && message.TryGetProperty("content", out var content) ? content.GetString() : null;

    private static string? ExtractText(JsonElement root)
    {
        if (!root.TryGetProperty("output", out var output) || output.ValueKind != JsonValueKind.Array) return null;
        var parts = new List<string>(); foreach (var item in output.EnumerateArray()) if (item.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array) foreach (var c in content.EnumerateArray()) if (c.TryGetProperty("text", out var text)) parts.Add(text.GetString() ?? string.Empty);
        return string.Join("\n", parts);
    }
}
