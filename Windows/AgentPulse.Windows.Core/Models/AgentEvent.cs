using System.Text.Json.Serialization;

namespace AgentPulse.Windows.Core.Models;

public sealed class AgentEvent
{
    [JsonPropertyName("session_id")]
    public required string SessionId { get; init; }

    [JsonPropertyName("agent")]
    public required string Agent { get; init; }

    [JsonPropertyName("cwd")]
    public required string Cwd { get; init; }

    [JsonPropertyName("title")]
    public string? Title { get; init; }

    [JsonPropertyName("phase")]
    public required string Phase { get; init; }

    [JsonPropertyName("detail")]
    public string? Detail { get; init; }

    [JsonPropertyName("pid")]
    public int? ProcessId { get; init; }

    [JsonPropertyName("tty")]
    public string? Tty { get; init; }

    [JsonPropertyName("terminal_bundle_id")]
    public string? TerminalBundleId { get; init; }

    [JsonPropertyName("terminal_process")]
    public string? TerminalProcess { get; init; }

    [JsonPropertyName("occurred_at")]
    public DateTimeOffset? OccurredAt { get; init; }
}
