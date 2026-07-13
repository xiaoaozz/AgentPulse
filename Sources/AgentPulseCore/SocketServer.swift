import Darwin
import Foundation

public final class SocketServer: @unchecked Sendable {
    public static let defaultPath = "/tmp/agentpulse.sock"

    private let path: String
    private let queue = DispatchQueue(label: "app.agentpulse.socket", qos: .userInitiated)
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private let onEvent: (AgentEvent) -> Void
    private let onError: (Error) -> Void

    public init(
        path: String = SocketServer.defaultPath,
        onEvent: @escaping (AgentEvent) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.path = path
        self.onEvent = onEvent
        self.onError = onError
    }

    public func start() {
        queue.async { [weak self] in self?.startOnQueue() }
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
            unlink(path)
        }
    }

    deinit {
        source?.cancel()
        if descriptor >= 0 { Darwin.close(descriptor) }
        unlink(path)
    }

    private func startOnQueue() {
        guard descriptor < 0 else { return }
        unlink(path)
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return emitPOSIXError() }
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            return onError(SocketError.pathTooLong)
        }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), source, capacity - 1)
            }
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { return emitPOSIXError() }
        chmod(path, 0o600)
        guard listen(descriptor, 16) == 0 else { return emitPOSIXError() }

        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source?.setEventHandler { [weak self] in self?.acceptConnections() }
        source?.resume()
    }

    private func acceptConnections() {
        while true {
            let client = accept(descriptor, nil, nil)
            if client < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK { emitPOSIXError() }
                return
            }
            prepare(client: client)
            read(client: client)
            Darwin.close(client)
        }
    }

    /// Accepted sockets inherit `O_NONBLOCK` from the listening socket on
    /// Darwin. A client such as Node may connect first and enqueue its payload
    /// on the next event-loop turn. Reading immediately would see `EAGAIN`,
    /// discard the empty event, and close the connection before that write.
    private func prepare(client: Int32) {
        let flags = fcntl(client, F_GETFL)
        if flags >= 0 {
            _ = fcntl(client, F_SETFL, flags & ~O_NONBLOCK)
        }

        // Do not let a connected client that never writes block the listener.
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        withUnsafePointer(to: &timeout) { pointer in
            _ = setsockopt(
                client,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }
    }

    private func read(client: Int32) {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.read(client, &buffer, buffer.count)
            if count > 0 { result.append(contentsOf: buffer.prefix(count)) }
            else { break }
        }
        guard !result.isEmpty else { return }
        do { onEvent(try EventDecoder.decode(result)) }
        catch { onError(error) }
    }

    private func emitPOSIXError() {
        onError(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
    }
}

public enum SocketError: LocalizedError {
    case pathTooLong
    public var errorDescription: String? { "Unix socket 路径过长" }
}
