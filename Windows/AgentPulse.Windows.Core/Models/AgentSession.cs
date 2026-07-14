namespace AgentPulse.Windows.Core.Models;

public sealed class AgentSession
{
    public required string Id { get; init; }
    public required string Agent { get; init; }
    public required string Cwd { get; init; }
    public required string Title { get; init; }
    public required SessionPhase Phase { get; init; }
    public string? Detail { get; init; }
    public int? ProcessId { get; init; }
    public string? Tty { get; init; }
    public string? TerminalProcess { get; init; }
    public required DateTimeOffset UpdatedAt { get; init; }

    public bool CanRemove => Phase.IsClearable();
    public string PhaseLabel => Phase.Label();
    public string Headline => string.IsNullOrWhiteSpace(Detail) ? Title : Detail;
    public string Subtitle => string.IsNullOrWhiteSpace(Detail) ? PhaseLabel : Title;

    public static AgentSession FromEvent(AgentEvent value, DateTimeOffset? now = null) => new()
    {
        Id = value.SessionId,
        Agent = value.Agent,
        Cwd = value.Cwd,
        Title = NonBlank(value.Title) ?? ProjectName(value.Cwd),
        Phase = SessionPhaseExtensions.FromProtocolValue(value.Phase),
        Detail = NonBlank(value.Detail),
        ProcessId = value.ProcessId,
        Tty = value.Tty,
        TerminalProcess = value.TerminalProcess,
        UpdatedAt = value.OccurredAt ?? now ?? DateTimeOffset.UtcNow,
    };

    public AgentSession Applying(AgentEvent value, DateTimeOffset? now = null) => new()
    {
        Id = Id,
        Agent = value.Agent,
        Cwd = value.Cwd,
        Title = NonBlank(value.Title) ?? Title,
        Phase = SessionPhaseExtensions.FromProtocolValue(value.Phase),
        Detail = NonBlank(value.Detail) ?? Detail,
        ProcessId = value.ProcessId ?? ProcessId,
        Tty = value.Tty ?? Tty,
        TerminalProcess = value.TerminalProcess ?? TerminalProcess,
        UpdatedAt = value.OccurredAt ?? now ?? DateTimeOffset.UtcNow,
    };

    private static string? NonBlank(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string ProjectName(string cwd)
    {
        var value = cwd.TrimEnd('/', '\\');
        var separator = Math.Max(value.LastIndexOf('/'), value.LastIndexOf('\\'));
        return separator >= 0 && separator + 1 < value.Length ? value[(separator + 1)..] : value;
    }
}
