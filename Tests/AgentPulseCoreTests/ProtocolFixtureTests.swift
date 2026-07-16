import Foundation
import XCTest
@testable import AgentPulseCore

@MainActor
final class ProtocolFixtureTests: XCTestCase {
    func testSharedSessionScenarios() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Protocol/Fixtures/session-scenarios.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixture = try decoder.decode(ProtocolFixture.self, from: Data(contentsOf: fixtureURL))

        XCTAssertEqual(fixture.protocolVersion, 1)
        for scenario in fixture.scenarios {
            let repository = SessionRepository()
            scenario.events.forEach { repository.receive($0) }

            XCTAssertEqual(repository.sessions.map(\.id), scenario.expectedOrder, scenario.name)
            XCTAssertEqual(repository.ongoingCount, scenario.expectedOngoingCount, scenario.name)
            XCTAssertEqual(repository.clearableCount, scenario.expectedClearableCount, scenario.name)
            if let expectedPhases = scenario.expectedPhases {
                for (id, phase) in expectedPhases {
                    XCTAssertEqual(
                        repository.sessions.first(where: { $0.id == id })?.phase.rawValue,
                        phase,
                        "\(scenario.name): \(id) phase"
                    )
                }
            }

            scenario.removeIds.forEach { repository.removeCompletedSession(id: $0) }
            XCTAssertEqual(
                repository.sessions.map(\.id),
                scenario.expectedOrderAfterRemovals,
                scenario.name
            )
        }
    }
}

private struct ProtocolFixture: Decodable {
    let protocolVersion: Int
    let scenarios: [SessionScenario]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case scenarios
    }
}

private struct SessionScenario: Decodable {
    let name: String
    let events: [AgentEvent]
    let expectedOrder: [String]
    let expectedPhases: [String: String]?
    let expectedOngoingCount: Int
    let expectedClearableCount: Int
    let removeIds: [String]
    let expectedOrderAfterRemovals: [String]

    enum CodingKeys: String, CodingKey {
        case name, events
        case expectedOrder = "expected_order"
        case expectedPhases = "expected_phases"
        case expectedOngoingCount = "expected_ongoing_count"
        case expectedClearableCount = "expected_clearable_count"
        case removeIds = "remove_ids"
        case expectedOrderAfterRemovals = "expected_order_after_removals"
    }
}
