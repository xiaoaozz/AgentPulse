using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using AgentPulse.Windows.Core.Models;

namespace AgentPulse.Windows.Core.Services;

public sealed class SessionRepository : INotifyPropertyChanged
{
    public static readonly TimeSpan DoneDisplayDuration = TimeSpan.FromSeconds(5);
    public ObservableCollection<AgentSession> Sessions { get; } = [];

    public int AttentionCount => Sessions.Count(session => session.Phase.NeedsAttention());
    public int OngoingCount => Sessions.Count(session => session.Phase.IsOngoing());
    public int ClearableCount => Sessions.Count(session => session.Phase.IsClearable());
    public bool HasClearable => ClearableCount > 0;
    public SessionPhase GlobalPhase => GlobalPhaseAt(DateTimeOffset.UtcNow);

    public SessionPhase GlobalPhaseAt(DateTimeOffset now)
    {
        var ongoing = Sessions.FirstOrDefault(session =>
            session.Phase.NeedsAttention() || session.Phase.IsActive());
        if (ongoing is not null) return ongoing.Phase;

        var latest = Sessions.MaxBy(session => session.UpdatedAt);
        if (latest?.Phase != SessionPhase.Done) return SessionPhase.Ready;
        var elapsed = now - latest.UpdatedAt;
        return elapsed >= TimeSpan.Zero && elapsed < DoneDisplayDuration
            ? SessionPhase.Done
            : SessionPhase.Ready;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public void Receive(AgentEvent value, DateTimeOffset? now = null)
    {
        var candidateTime = value.OccurredAt ?? now ?? DateTimeOffset.UtcNow;
        var current = Sessions.FirstOrDefault(session => session.Id == value.SessionId);
        if (current is not null && candidateTime < current.UpdatedAt) return;
        var updated = current is null
            ? AgentSession.FromEvent(value, candidateTime)
            : current.Applying(value, candidateTime);
        var sorted = Sessions
            .Where(session => session.Id != value.SessionId)
            .Append(updated)
            .OrderBy(session => Priority(session.Phase))
            .ThenByDescending(session => session.UpdatedAt)
            .ToArray();
        ReplaceAll(sorted);
    }

    public void RemoveCompletedSession(string id)
    {
        var session = Sessions.FirstOrDefault(value => value.Id == id);
        if (session is null || !session.Phase.IsClearable()) return;
        Sessions.Remove(session);
        NotifyCounts();
    }

    public void ClearCompleted()
    {
        var remaining = Sessions.Where(session => !session.Phase.IsClearable()).ToArray();
        ReplaceAll(remaining);
    }

    private void ReplaceAll(IEnumerable<AgentSession> values)
    {
        Sessions.Clear();
        foreach (var value in values) Sessions.Add(value);
        NotifyCounts();
    }

    private void NotifyCounts()
    {
        OnPropertyChanged(nameof(AttentionCount));
        OnPropertyChanged(nameof(OngoingCount));
        OnPropertyChanged(nameof(ClearableCount));
        OnPropertyChanged(nameof(HasClearable));
        OnPropertyChanged(nameof(GlobalPhase));
    }

    private static int Priority(SessionPhase phase)
    {
        if (phase.NeedsAttention()) return 0;
        if (phase.IsActive()) return 1;
        if (phase == SessionPhase.Ready) return 2;
        if (phase.IsClearable()) return 3;
        return 5;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
