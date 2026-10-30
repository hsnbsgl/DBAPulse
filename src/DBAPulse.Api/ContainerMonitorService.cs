using System.Net.Sockets;
using System.Text.Json;

namespace DBAPulse.Api;

public sealed record ContainerSummary(string Id, string Name, string Image, string State, string Status, bool Running);

public sealed class ContainerMonitorService
{
    private readonly HttpClient _client;

    public ContainerMonitorService()
    {
        var handler = new SocketsHttpHandler
        {
            ConnectCallback = async (_, cancellationToken) =>
            {
                var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
                await socket.ConnectAsync(new UnixDomainSocketEndPoint("/var/run/docker.sock"), cancellationToken);
                return new NetworkStream(socket, ownsSocket: true);
            }
        };
        _client = new HttpClient(handler) { BaseAddress = new Uri("http://docker.local") };
    }

    public async Task<IReadOnlyList<ContainerSummary>> ListAsync(CancellationToken token)
    {
        using var response = await _client.GetAsync("/containers/json?all=1", token);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(token);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: token);
        return document.RootElement.EnumerateArray().Select(container =>
        {
            var names = container.TryGetProperty("Names", out var nameElement)
                ? nameElement.EnumerateArray().Select(name => name.GetString()?.TrimStart('/') ?? string.Empty).Where(name => name.Length > 0).ToArray()
                : Array.Empty<string>();
            var state = container.TryGetProperty("State", out var stateElement) ? stateElement.GetString() ?? "unknown" : "unknown";
            return new ContainerSummary(
                container.GetProperty("Id").GetString() ?? string.Empty,
                names.FirstOrDefault() ?? "(unnamed)",
                container.TryGetProperty("Image", out var image) ? image.GetString() ?? string.Empty : string.Empty,
                state,
                container.TryGetProperty("Status", out var status) ? status.GetString() ?? string.Empty : string.Empty,
                string.Equals(state, "running", StringComparison.OrdinalIgnoreCase));
        }).OrderByDescending(container => container.Running).ThenBy(container => container.Name, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    public async Task<string> LogsAsync(string containerId, int tail, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(containerId) || containerId.Any(character => !(char.IsLetterOrDigit(character) || character is '_' or '-' or '.')))
            throw new ArgumentException("Invalid container id.", nameof(containerId));

        tail = Math.Clamp(tail, 1, 1000);
        using var response = await _client.GetAsync($"/containers/{containerId}/logs?stdout=1&stderr=1&timestamps=1&tail={tail}", HttpCompletionOption.ResponseHeadersRead, token);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(token);
        using var memory = new MemoryStream();
        await stream.CopyToAsync(memory, token);
        return DecodeDockerLogFrames(memory.ToArray());
    }

    private static string DecodeDockerLogFrames(byte[] bytes)
    {
        if (bytes.Length < 8) return System.Text.Encoding.UTF8.GetString(bytes);
        using var output = new MemoryStream();
        var offset = 0;
        while (offset + 8 <= bytes.Length)
        {
            var size = (bytes[offset + 4] << 24) | (bytes[offset + 5] << 16) | (bytes[offset + 6] << 8) | bytes[offset + 7];
            if (size < 0 || offset + 8 + size > bytes.Length) return System.Text.Encoding.UTF8.GetString(bytes);
            output.Write(bytes, offset + 8, size);
            offset += 8 + size;
        }
        if (offset != bytes.Length) return System.Text.Encoding.UTF8.GetString(bytes);
        return System.Text.Encoding.UTF8.GetString(output.ToArray());
    }
}
