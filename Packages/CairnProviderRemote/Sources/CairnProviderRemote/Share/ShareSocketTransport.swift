import CairnChatDomain
import Foundation
import Network

/// One client's socket, seen as bytes in and bytes out.
///
/// **Why this is `@unchecked Sendable` and not an actor.** Every `NWConnection` callback is delivered
/// on the one serial queue this transport owns, and every method here hops onto that queue before it
/// touches the connection. The class is therefore queue-confined, which is the guarantee the Network
/// framework is built around and which the type system cannot express for a Network object. The rule
/// that keeps this safe is one line long: nothing touches `connection` off `queue`.
final class ShareSocket: ShareFrameWriting, @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// Reads until the parser has a whole request, has rejected one, or the client stops talking.
    /// `needMoreBytes` on return means the peer went away mid-request: the caller closes, and a
    /// partial request is never answered as if it had arrived whole.
    func readRequest() async -> ShareParseOutcome {
        await withCheckedContinuation { continuation in
            queue.async { self.receive(then: continuation) }
        }
    }

    private func receive(then continuation: CheckedContinuation<ShareParseOutcome, Never>) {
        switch ShareHTTPParser.parse(buffer) {
        case .complete(let request):
            continuation.resume(returning: .complete(request))
        case .rejected(let failure):
            continuation.resume(returning: .rejected(failure))
        case .needMoreBytes:
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] received, _, isComplete, error in
                guard let self else {
                    continuation.resume(returning: .needMoreBytes)
                    return
                }
                if let received, !received.isEmpty { self.buffer.append(received) }
                guard error == nil, !isComplete else {
                    // A whole request may already be sitting in the buffer, so read it once more
                    // before giving up: a client that half-closes after its last byte still gets an
                    // answer rather than a dropped connection.
                    continuation.resume(returning: ShareHTTPParser.parse(self.buffer))
                    return
                }
                self.queue.async { self.receive(then: continuation) }
            }
        }
    }

    func writeHead(_ reply: ShareReply) async { await writeBytes(reply.headData) }
    func writeFrame(_ frame: String) async { await writeBytes(Data(frame.utf8)) }

    /// Ends the answer. A streamed response carries no Content-Length, so **the close is the
    /// terminator** — a client left holding an open socket is a client still waiting for an answer.
    func finishWriting() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard self.connection.state == .ready else {
                    self.connection.cancel()
                    continuation.resume()
                    return
                }
                // `isComplete: true` flushes what is already queued before the completion runs, so
                // the last frame is on the wire before the socket closes.
                self.connection.send(content: nil, contentContext: .default, isComplete: true,
                                     completion: .contentProcessed { _ in
                    self.connection.cancel()
                    continuation.resume()
                })
            }
        }
    }

    private func writeBytes(_ bytes: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard self.connection.state == .ready, !bytes.isEmpty else {
                    continuation.resume()
                    return
                }
                self.connection.send(content: bytes, contentContext: .default, isComplete: false,
                                     completion: .contentProcessed { _ in
                    continuation.resume()
                })
            }
        }
    }

    func abandon() {
        queue.async { self.connection.cancel() }
    }
}

/// The listening side: one address, one port, one serial queue for every callback.
///
/// The bind is **one address, never a wildcard**. A wildcard listener means "every interface this
/// phone has", and one of those interfaces is whatever the cellular carrier handed out — a port open
/// to the internet that the user never asked for and cannot see. Binding the address the policy
/// picked means exactly one interface, and `SharePolicy` has already refused any address that is not
/// a private LAN address before this code is reached.
final class ShareSocketTransport: @unchecked Sendable {
    let queue: DispatchQueue
    private var listener: NWListener?

    var onConnection: (@Sendable (ShareSocket) -> Void)?

    init(queueLabel: String = "app.cairn.share.socket") {
        queue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    /// Binds and waits for the port to come up. False means it is not listening; the caller reports a
    /// refusal code rather than an address or a system error string, because neither belongs in a log.
    func start(address: String, port: Int) async -> Bool {
        guard let rawPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: rawPort)

        let created: NWListener
        do {
            created = try NWListener(using: parameters, on: rawPort)
        } catch {
            return false
        }
        created.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.onConnection?(ShareSocket(connection: connection, queue: self.queue))
        }

        let latch = ResumeOnce()
        let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            created.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if latch.claim() { continuation.resume(returning: true) }
                case .failed, .cancelled:
                    if latch.claim() { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            created.start(queue: queue)
        }
        guard ready else {
            created.cancel()
            return false
        }
        queue.async { self.listener = created }
        return true
    }

    /// Stops listening. Connections already open are left to finish the answer they are mid-way
    /// through: yanking a socket out from under a streaming reply is how a client ends up with half
    /// an answer and no reason.
    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }
}

/// A latch, because a listener can report `.ready` and then `.failed`, and a continuation resumed
/// twice is a crash — which is a worse answer than a refused port.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
