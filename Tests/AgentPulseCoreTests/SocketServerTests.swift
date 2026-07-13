import Darwin
import Foundation
import XCTest
@testable import AgentPulseCore

final class SocketServerTests: XCTestCase {
    func testReadsPayloadWrittenShortlyAfterConnect() throws {
        let path = "/tmp/agentpulse-test-\(UUID().uuidString).sock"
        let received = expectation(description: "server receives delayed payload")
        let server = SocketServer(path: path) { event in
            XCTAssertEqual(event.sessionId, "delayed-node-style-client")
            XCTAssertEqual(event.phase, .done)
            received.fulfill()
        }
        server.start()
        defer { server.stop() }

        let deadline = Date().addingTimeInterval(1)
        while !FileManager.default.fileExists(atPath: path), Date() < deadline {
            usleep(5_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(client, 0)
        defer { Darwin.close(client) }

        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    source,
                    pathCapacity - 1
                )
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connected, 0)

        // Node's net client writes from its connect callback, after the server
        // can already have accepted the connection.
        usleep(50_000)
        let payload = Data(#"{"session_id":"delayed-node-style-client","agent":"Codex","cwd":"/tmp","phase":"done"}"#.utf8)
        let written = payload.withUnsafeBytes { bytes in
            Darwin.write(client, bytes.baseAddress, bytes.count)
        }
        XCTAssertEqual(written, payload.count)
        Darwin.shutdown(client, SHUT_WR)

        wait(for: [received], timeout: 1)
    }
}
