import Foundation
import XCTest
@testable import AgentPulseCore

final class EventDecoderTests: XCTestCase {
    func testDecodesHookTimestampWithFractionalSeconds() throws {
        let data = Data(#"{"session_id":"fractional","agent":"Codex","cwd":"/tmp","phase":"running","occurred_at":"2026-07-13T07:58:12.345Z"}"#.utf8)

        let event = try EventDecoder.decode(data)

        XCTAssertEqual(event.sessionId, "fractional")
        XCTAssertNotNil(event.occurredAt)
    }

    func testDecodesHookTimestampWithoutFractionalSeconds() throws {
        let data = Data(#"{"session_id":"seconds","agent":"Codex","cwd":"/tmp","phase":"done","occurred_at":"2026-07-13T07:58:12Z"}"#.utf8)

        let event = try EventDecoder.decode(data)

        XCTAssertEqual(event.sessionId, "seconds")
        XCTAssertNotNil(event.occurredAt)
    }
}
