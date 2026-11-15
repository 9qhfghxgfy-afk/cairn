import Foundation
import Network

/// Boxes the connection so the dispatch and Network callbacks can be `@Sendable` without
/// depending on how this SDK revision annotates `NWConnection`.
private final class SocketBox: @unchecked Sendable {
    let connection: NWConnection

    init(_ connection: NWConnection) {
        self.connection = connection
    }
}

/// Minimal HTTP/1.1 responder on 127.0.0.1.
///
/// It exists so the URLSession delegate, the status-to-error mapping, and Stop are exercised
/// against the real network stack instead of a stub. Loopback needs no network access and no
/// ATS exception, so it is safe in CI.
final class LocalStubServer: @unchecked Sendable {
    struct Route {
        var path: String
        var status: Int = 200
        var contentType: String = "application/x-ndjson"
        /// Written one piece at a time, so a real stream arrives in real delegate callbacks.
        var pieces: [String] = []
        /// Nanoseconds between pieces.
        var gapNanoseconds: Int = 0
        /// Nanoseconds before anything is written: large enough to simulate a silent server.
        var openDelayNanoseconds: Int = 0
    }

    private let queue = DispatchQueue(label: "app.cairn.test.stub-server")
    private let listener: NWListener
    private let routes: [Route]
    private let lock = NSLock()
    private var live: [SocketBox] = []
    private var selfClosed: Set<ObjectIdentifier> = []
    private var failedSends = 0
    private var peerClosed = 0

    private init(listener: NWListener, routes: [Route]) {
        self.listener = listener
        self.routes = routes
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }
    var failedSendCount: Int { lock.lock(); defer { lock.unlock() }; return failedSends }
    var peerClosedCount: Int { lock.lock(); defer { lock.unlock() }; return peerClosed }

    /// nil when loopback cannot be bound, so the caller skips instead of failing CI.
    static func start(routes: [Route]) -> LocalStubServer? {
        guard let listener = try? NWListener(using: .tcp) else { return nil }
        let server = LocalStubServer(listener: listener, routes: routes)
        return server.begin() ? server : nil
    }

    func stop() {
        lock.lock()
        let sockets = live
        live.removeAll()
        for socket in sockets { selfClosed.insert(ObjectIdentifier(socket)) }
        lock.unlock()
        sockets.forEach { $0.connection.cancel() }
        listener.cancel()
    }

    private func begin() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(SocketBox(connection)) }
        listener.stateUpdateHandler = { state in
            // Wait for the listener to actually bind (or fail) before reading its port.
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.start(queue: queue)
        let outcome = ready.wait(timeout: .now() + 3)
        if outcome == .timedOut { return false }
        return listener.port != nil
    }

    private func accept(_ socket: SocketBox) {
        lock.lock()
        live.append(socket)
        lock.unlock()
        socket.connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.readRequest(from: socket)
            } else if case .failed = state {
                self?.notePeerClose(socket)
            } else if case .cancelled = state {
                self?.notePeerClose(socket)
            }
        }
        socket.connection.start(queue: queue)
    }

    private func readRequest(from socket: SocketBox) {
        socket.connection.receive(minimumIncompleteLength: 1, maximumExpectedLength: 4096) { [weak self] data, _, _, error in
            guard let self, error == nil, let data else {
                self?.close(socket)
                return
            }
            let path = Self.requestPath(data)
            let route = self.routes.first { $0.path == path }
                ?? Route(path: path, status: 404, contentType: "application/json", pieces: ["{}"])
            self.answer(socket, route: route)
        }
    }

    private func answer(_ socket: SocketBox, route: Route) {
        guard route.openDelayNanoseconds > 0 else {
            write(socket, route: route)
            return
        }
        queue.asyncAfter(deadline: .now() + .nanoseconds(route.openDelayNanoseconds)) { [weak self] in
            self?.write(socket, route: route)
        }
    }

    private func write(_ socket: SocketBox, route: Route) {
        let body = route.pieces.map { Data($0.utf8) }
        let head = Self.responseHead(
            status: route.status,
            contentType: route.contentType,
            byteCount: body.reduce(0) { $0 + $1.count }
        )
        send(socket, pieces: [head] + body, gap: route.gapNanoseconds)
    }

    private func send(_ socket: SocketBox, pieces: [Data], gap: Int) {
        guard let piece = pieces.first else {
            close(socket)
            return
        }
        let rest = Array(pieces.dropFirst())
        socket.connection.send(content: piece, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.noteFailedSend()
                self.close(socket)
                return
            }
            guard !rest.isEmpty else {
                // The body is complete. Leave the socket open: URLSession finishes the task on
                // Content-Length and closes from its side, which is the client-close path.
                return
            }
            guard gap > 0 else {
                self.send(socket, pieces: rest, gap: gap)
                return
            }
            self.queue.asyncAfter(deadline: .now() + .nanoseconds(gap)) {
                self.send(socket, pieces: rest, gap: gap)
            }
        })
    }

    private func close(_ socket: SocketBox) {
        lock.lock()
        selfClosed.insert(ObjectIdentifier(socket))
        live.removeAll { $0 === socket }
        lock.unlock()
        socket.connection.cancel()
    }

    /// Counts a close this server did not start: that is the client walking away, which is
    /// exactly what Stop has to cause.
    private func notePeerClose(_ socket: SocketBox) {
        lock.lock()
        if !selfClosed.contains(ObjectIdentifier(socket)) { peerClosed += 1 }
        lock.unlock()
    }

    private func noteFailedSend() {
        lock.lock()
        failedSends += 1
        lock.unlock()
    }
}
