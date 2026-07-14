namespace AgentPulse.Windows.Core.Models;

public enum SessionPhase
{
    Idle,
    Preparing,
    Running,
    WaitingForAction,
    Done,
    Warning,
    Failed,
    Paused,
    Offline,
}

public static class SessionPhaseExtensions
{
    public static bool NeedsAttention(this SessionPhase phase) => phase == SessionPhase.WaitingForAction;

    public static bool IsActive(this SessionPhase phase) =>
        phase is SessionPhase.Preparing or SessionPhase.Running;

    public static bool IsClearable(this SessionPhase phase) =>
        phase is SessionPhase.Done or SessionPhase.Warning or SessionPhase.Failed;

    public static bool IsOngoing(this SessionPhase phase) =>
        phase.IsActive() || phase.NeedsAttention() || phase == SessionPhase.Paused;

    public static string Label(this SessionPhase phase) => phase switch
    {
        SessionPhase.Idle => "Idle",
        SessionPhase.Preparing => "Preparing",
        SessionPhase.Running => "Running",
        SessionPhase.WaitingForAction => "Waiting for Action",
        SessionPhase.Done => "Done",
        SessionPhase.Warning => "Warning",
        SessionPhase.Failed => "Failed",
        SessionPhase.Paused => "Paused",
        SessionPhase.Offline => "Offline",
        _ => phase.ToString(),
    };

    public static SessionPhase FromProtocolValue(string value) => value switch
    {
        "idle" => SessionPhase.Idle,
        "preparing" => SessionPhase.Preparing,
        "running" => SessionPhase.Running,
        "waiting_for_action" => SessionPhase.WaitingForAction,
        "done" => SessionPhase.Done,
        "warning" => SessionPhase.Warning,
        "failed" => SessionPhase.Failed,
        "paused" => SessionPhase.Paused,
        "offline" => SessionPhase.Offline,
        _ => throw new ArgumentException($"Unsupported AgentPulse phase: {value}", nameof(value)),
    };
}
