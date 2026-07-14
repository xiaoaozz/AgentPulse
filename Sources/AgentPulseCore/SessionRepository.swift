import Combine
import Foundation

@MainActor
public final class SessionRepository: ObservableObject {
    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var lastError: String?

    public init() {}

    public var attentionCount: Int { sessions.count { $0.phase.needsAttention } }
    public var activeCount: Int { sessions.count { $0.phase.isActive } }
    public var clearableCount: Int { sessions.count { $0.phase.isClearable } }
    /// Count shown in the menu bar and notch. Terminal result sessions remain
    /// visible in the list, but do not contribute to the live session count.
    public var ongoingCount: Int { sessions.count { $0.phase.isOngoing } }

    public func receive(_ event: AgentEvent, now: Date = .now) {
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            sessions[index].apply(event, now: now)
        } else {
            sessions.append(AgentSession(event: event, now: now))
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
        if phase == .paused { return 2 }
        if phase == .idle { return 3 }
        if phase.isClearable { return 4 }
        return 5
    }
}
