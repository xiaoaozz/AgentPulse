import XCTest
@testable import AgentPulseCore

@MainActor
final class SessionRepositoryTests: XCTestCase {
    func testAttentionSessionsSortFirstAndUpdateInPlace() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "a", agent: "Codex", cwd: "/tmp/A", phase: .running))
        repository.receive(.init(sessionId: "b", agent: "Codex", cwd: "/tmp/B", phase: .waitingForAction))

        XCTAssertEqual(repository.sessions.map(\.id), ["b", "a"])
        XCTAssertEqual(repository.attentionCount, 1)

        repository.receive(.init(sessionId: "b", agent: "Codex", cwd: "/tmp/B", phase: .running))
        XCTAssertEqual(repository.sessions.count, 2)
        XCTAssertEqual(repository.attentionCount, 0)
    }

    func testCompletedSessionsRemainUntilCleared() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "a", agent: "Custom", cwd: "/tmp/A", phase: .done))
        XCTAssertEqual(repository.sessions.count, 1)
        XCTAssertEqual(repository.ongoingCount, 0)
        repository.clearCompleted()
        XCTAssertTrue(repository.sessions.isEmpty)
    }

    func testRemovingOneCompletedSessionDoesNotRemoveActiveSessions() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "running", agent: "Custom", cwd: "/tmp/A", phase: .running))
        repository.receive(.init(sessionId: "done", agent: "Custom", cwd: "/tmp/B", phase: .done))

        repository.removeCompletedSession(id: "running")
        XCTAssertEqual(repository.sessions.map(\.id), ["running", "done"])

        repository.removeCompletedSession(id: "done")
        XCTAssertEqual(repository.sessions.map(\.id), ["running"])
    }

    func testResultSessionsDoNotContributeToOngoingCount() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "running", agent: "Custom", cwd: "/tmp/A", phase: .running))
        repository.receive(.init(sessionId: "done", agent: "Custom", cwd: "/tmp/B", phase: .done))
        repository.receive(.init(sessionId: "warning", agent: "Custom", cwd: "/tmp/C", phase: .warning))
        repository.receive(.init(sessionId: "failed", agent: "Custom", cwd: "/tmp/D", phase: .failed))

        XCTAssertEqual(repository.sessions.count, 4)
        XCTAssertEqual(repository.ongoingCount, 1)
    }

    func testIdleAndOfflineSessionsDoNotContributeToOngoingCount() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "idle", agent: "Codex", cwd: "/tmp/A", phase: .idle))
        repository.receive(.init(sessionId: "offline", agent: "Codex", cwd: "/tmp/B", phase: .offline))
        repository.receive(.init(sessionId: "waiting", agent: "Codex", cwd: "/tmp/C", phase: .waitingForAction))

        XCTAssertEqual(repository.sessions.count, 3)
        XCTAssertEqual(repository.ongoingCount, 1)
    }

    func testInterruptedSessionRemainsVisibleButLeavesOngoingCount() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "interrupted", agent: "Codex", cwd: "/tmp/A", phase: .running))
        XCTAssertEqual(repository.ongoingCount, 1)

        repository.receive(.init(sessionId: "interrupted", agent: "Codex", cwd: "/tmp/A", phase: .paused))

        XCTAssertEqual(repository.sessions.map(\.id), ["interrupted"])
        XCTAssertEqual(repository.sessions.first?.phase, .paused)
        XCTAssertEqual(repository.ongoingCount, 0)
    }

    func testMissingDetailKeepsLastAgentSummary() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "a", agent: "Custom", cwd: "/tmp/A", phase: .running, detail: "正在分析代码"))
        repository.receive(.init(sessionId: "a", agent: "Custom", cwd: "/tmp/A", phase: .done))
        XCTAssertEqual(repository.sessions.first?.detail, "正在分析代码")
    }
}
