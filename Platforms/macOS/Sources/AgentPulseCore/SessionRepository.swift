import Combine
import Foundation

@MainActor
public final class SessionRepository: ObservableObject {
    public static let doneDisplayDuration: TimeInterval = 5
    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var lastError: String?

    public init() {}

    public var attentionCount: Int { sessions.count { $0.phase.needsAttention } }
    public var activeCount: Int { sessions.count { $0.phase.isActive } }
    public var clearableCount: Int { sessions.count { $0.phase.isClearable } }
    /// Count shown in the menu bar and notch. Terminal result sessions remain
    /// visible in the list, but do not contribute to the live session count.
    public var ongoingCount: Int { sessions.count { $0.phase.isOngoing } }
    /// Status shown by the collapsed global surface. Historical states such as
    /// Terminal results remain visible per session, but do not keep the
    /// whole app in that state when no work is currently ongoing.
    public var globalPhase: SessionPhase { globalPhase(at: .now) }

    public func globalPhase(at now: Date) -> SessionPhase {
        if let ongoing = sessions.first(where: { $0.phase.needsAttention || $0.phase.isActive }) {
            return ongoing.phase
        }

        guard let latest = sessions.max(by: { $0.updatedAt < $1.updatedAt }), latest.phase == .done else {
            return .ready
        }
        let elapsed = now.timeIntervalSince(latest.updatedAt)
        return elapsed >= 0 && elapsed < Self.doneDisplayDuration ? .done : .ready
    }

    public func receive(_ event: AgentEvent, now: Date = .now) {
        let candidateTime = event.occurredAt ?? now
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            guard sessions[index].apply(event, at: candidateTime) else { return }
        } else {
            sessions.append(AgentSession(event: event, now: candidateTime))
        }
        sortSessions()
    }

    public func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    public func clearCompleted() {
        sessions.removeAll { $0.phase.isClearable }
    }

    public func removeCompletedSession(id: AgentSession.ID) {
        sessions.removeAll { $0.id == id && $0.phase.isClearable }
    }

    private func sortSessions() {
        sessions.sort {
            let left = priority($0.phase)
            let right = priority($1.phase)
            return left == right ? $0.updatedAt > $1.updatedAt : left < right
        }
    }

    private func priority(_ phase: SessionPhase) -> Int {
        if phase.needsAttention { return 0 }
        if phase.isActive { return 1 }
        if phase == .ready { return 2 }
        if phase.isClearable { return 3 }
        return 5
    }
}
