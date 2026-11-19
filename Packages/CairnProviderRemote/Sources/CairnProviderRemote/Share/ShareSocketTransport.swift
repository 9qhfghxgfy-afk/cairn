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

    /// Starts this accepted connection and waits until it can carry bytes.
    ///
    /// **An `NWConnection` handed over by a listener is not started.** Apple delivers it in the setup
    /// state and makes the accept site call `start(queue:)`; reading before that waits for bytes the
    /// stack will never deliver, which looks to a client like a phone that accepts and then goes
    /// silent. False means the peer failed or went away before the connection came up — answered by
    /// closing, never by pretending a turn ran.
    func begin() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let latch = ResumeOnce()
            queue.async {
                self.connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if latch.claim() { continuation.resume(returning: true) }
                    case .failed, .cancelled:
                        if latch.claim() { continuation.resume(returning: false) }
                    default:
                        break
                    }
                }
                self.connection.start(queue: self.queue)
            }
        }
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

    /// The head **and whatever body the reply carries**, as one write.
    ///
    /// `ShareReply` keeps its body pieces in `frames`, so a buffered answer's body is the reply. Writing
    /// only the head here would print a `Content-Length` and then close without filling it, which a real
    /// client reports as a lost connection rather than as a short answer — so this writes both, in one
    /// send, and the caller cannot get one without the other.
    func writeReply(_ reply: ShareReply) async { await writeBytes(reply.allBytes) }
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
                // the last frame is on the wire before the socket closes. `.finalMessage` is Apple's
                // own "this is the last one" context — the documented way to end a connection. Note
                // there is no `.default` on `NWConnection.ContentContext`: the constant send contexts
                // are `defaultMessage`, `finalMessage` and `defaultStream`.
                self.connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
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
                self.connection.send(content: bytes, contentContext: .defaultMessage, isComplete: false,
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

/// The listening side: one port, one serial queue for every callback, and a bind as tight as the system
/// will grant.
///
/// **The intent is one address, never a wildcard** — a wildcard listener means "every interface this phone
/// has", and one of those is whatever the cellular carrier handed out. The Network framework, however,
/// decides whether a listener may actually be pinned to one local endpoint, and it has been seen to
/// reject a listener started that way outright: on the CI runner, `NWListener(using:on:)` with a required
/// local endpoint failed in under a millisecond, which is a parameter rejection, not a busy port.
///
/// So the bind is tried in order of preference and the result is reported as a `ShareBindScope`: pinned to
/// the chosen address if the system allows it, otherwise the port bound on the device and **said out loud
/// on the screen**. What does not bend is the pair of rules the policy enforces before this code is ever
/// reached: the phone must have a private LAN address, and every request must carry the key.
final class ShareSocketTransport: @unchecked Sendable {
    let queue: DispatchQueue
    private var listener: NWListener?

    var onConnection: (@Sendable (ShareSocket) -> Void)?

    init(queueLabel: String = "app.cairn.share.socket") {
        queue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    /// Binds and waits for the port to come up. nil means it is not listening; the caller reports a
    /// refusal code rather than an address or a system error string, because neither belongs in a log.
    func start(address: String, port: Int) async -> ShareBindScope? {
        guard let rawPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        if await bind(address: address, port: rawPort, pinToAddress: true) { return .chosenAddress }
        if await bind(address: address, port: rawPort, pinToAddress: false) { return .deviceWide }
        return nil
    }

    /// One bind attempt. `pinToAddress` asks the stack to confine the listener to that local endpoint;
    /// when that attempt is refused, the caller retries without the request and records the weaker scope.
    private func bind(address: String, port rawPort: NWEndpoint.Port, pinToAddress: Bool) async -> Bool {
        let parameters = NWParameters.tcp
        // Set in both directions on purpose: `NWParameters.tcp` hands back a parameters object that this
        // code just mutates, and the second attempt must not inherit the first attempt's requirement.
        parameters.requiredLocalEndpoint = pinToAddress
            ? .hostPort(host: NWEndpoint.Host(address), port: rawPort)
            : nil

        let created: NWListener
        do {
            created = try NWListener(using: parameters, on: rawPort)
        } catch {
            // A rejected parameter, not a busy port. Neither the address nor the system error is
            // reportable, so the caller only learns that this strategy did not work.
            return false
        }
        created.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.onConnection?(ShareSocket(connection: connection, queue: self.queue))
        }

        let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let latch = ResumeOnce()
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
        // Handed to the queue rather than written here: `stop()` also runs on this queue, and keeping the
        // two on one FIFO queue is what makes "start then immediately stop" cancel the listener it was
        // given rather than race past it and leave the port open.
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
