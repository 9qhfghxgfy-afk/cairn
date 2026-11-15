import Foundation
import CairnChatDomain
@testable import CairnProviderRemote

/// Canned replies keyed by URL path, with every request recorded so endpoint choice and
/// header assembly can be asserted. No sockets: the stub half of the suite must pass on a
/// runner with no network at all.
final class StubTransport: RemoteTransport, @unchecked Sendable {
    struct Reply {
        var chunks: [[UInt8]]
        var status: Int?
        var errorBody: Data
        /// False keeps the stream open after the last chunk: a stalled server that only
        /// `abandon()` can close, which is what the Stop tests need.
        var finishes: Bool

        // Explicit init with defaults: the memberwise one would require `errorBody` and
        // `finishes` at every call site.
        init(chunks: [[UInt8]], status: Int? = nil, errorBody: Data = Data(), finishes: Bool = true) {
            self.chunks = chunks
            self.status = status
            self.errorBody = errorBody
            self.finishes = finishes
        }

        static func body(_ text: String) -> Reply { Reply(chunks: [Array(text.utf8)]) }
        static func pieces(_ pieces: [String]) -> Reply { Reply(chunks: pieces.map { Array($0.utf8) }) }
        /// Raw byte pieces, so a fixture can split a line inside a multibyte character.
        static func bytePieces(_ pieces: [[UInt8]]) -> Reply { Reply(chunks: pieces) }
        static func stalled(after first: String) -> Reply {
            Reply(chunks: [Array(first.utf8)], finishes: false)
        }
        static func rejected(status: Int, errorJSON: String = "{}") -> Reply {
            Reply(chunks: [], status: status, errorBody: Data(errorJSON.utf8))
        }
    }

    private let lock = NSLock()
    private var table: [String: Reply]
    private var seen: [URLRequest] = []
    private var abandoned = 0

    init(_ table: [String: Reply] = [:]) { self.table = table }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    var abandonCount: Int { lock.lock(); defer { lock.unlock() }; return abandoned }

    func open(_ request: URLRequest) -> RemoteByteStream {
        let path = request.url?.path ?? ""
        lock.lock()
        seen.append(request)
        let reply = table[path]
        lock.unlock()

        guard let reply else {
            return RemoteByteStream(
                bytes: AsyncThrowingStream(Data.self, bufferingPolicy: .unbounded) {
                    $0.finish(throwing: RemoteError.httpStatus(404, serverMessage: nil))
                },
                abandon: { self.noteAbandon() }
            )
        }
        if let status = reply.status, !(200..<300).contains(status) {
            let message = RemoteBodyDelegate.serverMessage(in: reply.errorBody)
            return RemoteByteStream(
                bytes: AsyncThrowingStream(Data.self, bufferingPolicy: .unbounded) {
                    $0.finish(throwing: RemoteError.httpStatus(status, serverMessage: message))
                },
                abandon: { self.noteAbandon() }
            )
        }

        let held = HeldStream()
        held.onClose = { [weak self] in self?.noteAbandon() }
        let bytes = AsyncThrowingStream(Data.self, bufferingPolicy: .unbounded) { continuation in
            for chunk in reply.chunks { continuation.yield(Data(chunk)) }
            if reply.finishes {
                continuation.finish()
            } else {
                held.bind(continuation)
            }
        }
        return RemoteByteStream(bytes: bytes, abandon: { held.close() })
    }

    private func noteAbandon() {
        lock.lock()
        abandoned += 1
        lock.unlock()
    }
}

/// Holds the continuation of a stalled stub stream so `abandon()` can close it, exactly like
/// the URLSession transport cancelling the task when the consumer walks away.
private final class HeldStream: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
    var onClose: (@Sendable () -> Void)?

    func bind(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func close() {
        lock.lock()
        let pending = continuation
        continuation = nil
        let hook = onClose
        onClose = nil
        lock.unlock()
        hook?()
        pending?.finish(throwing: CancellationError())
    }
}

