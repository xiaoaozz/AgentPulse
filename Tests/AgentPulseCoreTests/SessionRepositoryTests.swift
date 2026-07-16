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

    func testDoneIsShownGloballyForFiveSecondsThenReturnsToReady() {
        let repository = SessionRepository()
        let completedAt = Date(timeIntervalSince1970: 1_000)
        repository.receive(
            .init(sessionId: "done", agent: "Codex", cwd: "/tmp/A", phase: .done),
            now: completedAt
        )

        XCTAssertEqual(repository.globalPhase(at: completedAt), .done)
        XCTAssertEqual(repository.globalPhase(at: completedAt.addingTimeInterval(4.999)), .done)
        XCTAssertEqual(repository.globalPhase(at: completedAt.addingTimeInterval(5)), .ready)
    }

    func testNewEventReplacesTransientDoneGlobalState() {
        let repository = SessionRepository()
        let completedAt = Date(timeIntervalSince1970: 1_000)
        repository.receive(
            .init(sessionId: "done", agent: "Codex", cwd: "/tmp/A", phase: .done),
            now: completedAt
        )
        repository.receive(
            .init(sessionId: "new", agent: "Codex", cwd: "/tmp/B", phase: .ready),
            now: completedAt.addingTimeInterval(1)
        )

        XCTAssertEqual(repository.globalPhase(at: completedAt.addingTimeInterval(2)), .ready)
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

    func testReadyAndOfflineSessionsDoNotContributeToOngoingCount() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "ready", agent: "Codex", cwd: "/tmp/A", phase: .ready))
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
        XCTAssertEqual(repository.globalPhase, .ready)
    }

    func testGlobalPhaseIgnoresPausedSessionWhenOtherWorkNeedsAttention() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "interrupted", agent: "Codex", cwd: "/tmp/A", phase: .paused))
        repository.receive(.init(sessionId: "running", agent: "Codex", cwd: "/tmp/B", phase: .running))
        repository.receive(.init(sessionId: "waiting", agent: "Codex", cwd: "/tmp/C", phase: .waitingForAction))

        XCTAssertEqual(repository.globalPhase, .waitingForAction)
    }

    func testClearedInterruptedSessionIsRecreatedByNextTaskInSameConversation() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "same-conversation", agent: "Codex", cwd: "/tmp/A", phase: .paused))

        XCTAssertEqual(repository.clearableCount, 1)
        repository.removeCompletedSession(id: "same-conversation")
        XCTAssertTrue(repository.sessions.isEmpty)

        repository.receive(.init(
            sessionId: "same-conversation",
            agent: "Codex",
            cwd: "/tmp/A",
            title: "继续执行新任务",
            phase: .preparing
        ))

        XCTAssertEqual(repository.sessions.count, 1)
        XCTAssertEqual(repository.sessions.first?.title, "继续执行新任务")
        XCTAssertEqual(repository.sessions.first?.phase, .preparing)
        XCTAssertEqual(repository.ongoingCount, 1)
    }

    func testMissingDetailKeepsLastAgentSummary() {
        let repository = SessionRepository()
        repository.receive(.init(sessionId: "a", agent: "Custom", cwd: "/tmp/A", phase: .running, detail: "正在分析代码"))
        repository.receive(.init(sessionId: "a", agent: "Custom", cwd: "/tmp/A", phase: .done))
        XCTAssertEqual(repository.sessions.first?.detail, "正在分析代码")
    }

    func testOlderEventCannotRollSessionBackward() {
        let repository = SessionRepository()
        let newer = Date(timeIntervalSince1970: 200)
        let older = Date(timeIntervalSince1970: 100)

        repository.receive(.init(
            sessionId: "a",
            agent: "Codex",
            cwd: "/tmp/A",
            title: "Newest",
            phase: .done,
            detail: "finished",
            occurredAt: newer
        ))
        repository.receive(.init(
            sessionId: "a",
            agent: "Codex",
            cwd: "/tmp/A",
            title: "Older",
            phase: .running,
            detail: "stale",
            occurredAt: older
        ))

        XCTAssertEqual(repository.sessions.first?.phase, .done)
        XCTAssertEqual(repository.sessions.first?.title, "Newest")
        XCTAssertEqual(repository.sessions.first?.detail, "finished")
        XCTAssertEqual(repository.ongoingCount, 0)
    }

    func testEqualTimestampEventStillAppliesInArrivalOrder() {
        let repository = SessionRepository()
        let timestamp = Date(timeIntervalSince1970: 300)

        repository.receive(.init(sessionId: "a", agent: "Codex", cwd: "/tmp/A", phase: .running, occurredAt: timestamp))
        repository.receive(.init(sessionId: "a", agent: "Codex", cwd: "/tmp/A", phase: .done, occurredAt: timestamp))

        XCTAssertEqual(repository.sessions.first?.phase, .done)
        XCTAssertEqual(repository.ongoingCount, 0)
    }

    func testMissingTimestampUsesReceiveTimeAndStillApplies() {
        let repository = SessionRepository()
        let receivedAt = Date(timeIntervalSince1970: 400)

        repository.receive(.init(sessionId: "a", agent: "Codex", cwd: "/tmp/A", phase: .running), now: receivedAt)

        XCTAssertEqual(repository.sessions.first?.phase, .running)
        XCTAssertEqual(repository.sessions.first?.updatedAt, receivedAt)
        XCTAssertEqual(repository.ongoingCount, 1)
    }
}
