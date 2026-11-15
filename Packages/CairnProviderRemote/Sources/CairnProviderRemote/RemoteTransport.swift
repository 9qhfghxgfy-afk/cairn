import Foundation

/// A stream of response bytes plus the handle that abandons it.
///
/// The handle exists because cancelling a Swift task does not wake a blocked `for try await`
/// on an `AsyncThrowingStream`: something has to close the producer. Handing the caller the
/// close button is what makes Stop actually stop generation instead of hanging on a socket
/// the server still thinks is open.
public struct RemoteByteStream: Sendable {
    public var bytes: AsyncThrowingStream<Data, any Error>
    public var abandon: @Sendable () -> Void

    public init(
        bytes: AsyncThrowingStream<Data, any Error>,
        abandon: @escaping @Sendable () -> Void
    ) {
        self.bytes = bytes
        self.abandon = abandon
    }
}

/// Byte-level transport seam. Everything above it is testable with a stub; everything
/// below it is URLSession.
///
/// A stream throws `RemoteError.httpStatus` for a non-2xx response (after buffering a
/// little of the error body so the server's own message can be reported) and finishes
/// normally for a 2xx body, so callers never have to look at a URLResponse.
public protocol RemoteTransport: Sendable {
    func open(_ request: URLRequest) -> RemoteByteStream
    func exchange(_ request: URLRequest) async throws -> Data
}

public extension RemoteTransport {
    /// Non-streaming call for the small catalog endpoints.
    func exchange(_ request: URLRequest) async throws -> Data {
        let opened = open(request)
        return try await withTaskCancellationHandler {
            var body = Data()
            for try await chunk in opened.bytes {
                if Task.isCancelled { throw CancellationError() }
                body.append(chunk)
            }
            return body
        } onCancel: {
            opened.abandon()
        }
    }
}

/// Holds the session and task so the stream's `onTermination` closure can be `@Sendable`
/// without depending on how this SDK revision happens to annotate those classes.
final class SessionBox: @unchecked Sendable {
    private let session: URLSession
    private var task: URLSessionTask?
    private var didStop = false
    private let lock = NSLock()

    init(session: URLSession) {
        self.session = session
    }

    func attach(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    /// Cancels the request, then drops the session. Safe to call more than once: the stream
    /// terminates itself when the consumer stops reading, and `abandon` may arrive first.
    func stop() {
        lock.lock()
        let pending = task
        task = nil
        let alreadyStopped = didStop
        didStop = true
        lock.unlock()
        pending?.cancel()
        if !alreadyStopped {
            session.invalidateAndCancel()
        }
    }
}

/// URLSession transport.
///
/// The delegate API is used rather than `URLSession.bytes(for:)` on purpose: the task is
/// cancellable explicitly, the delegate queue is serial so chunk order is guaranteed, and
/// error mapping lives in one place. One short-lived session per stream keeps the timeout
/// profile (long idle allowance, capped total) per request without sharing state.
public struct URLSessionTransport: RemoteTransport {
    /// How long the connection may stay silent before it counts as dead. A thinking model
    /// can be silent for a while before its first token, so this is generous; total
    /// generation is bounded separately by `resourceTimeout`.
    public var idleTimeout: TimeInterval
    public var resourceTimeout: TimeInterval

    public init(idleTimeout: TimeInterval = 90, resourceTimeout: TimeInterval = 1_800) {
        self.idleTimeout = idleTimeout
        self.resourceTimeout = resourceTimeout
    }

    public func open(_ request: URLRequest) -> RemoteByteStream {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = nil
        configuration.waitsForConnectivity = false

        let delegate = RemoteBodyDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let box = SessionBox(session: session)

        let bytes = AsyncThrowingStream(Data.self, bufferingPolicy: .unbounded) { continuation in
            delegate.bind(continuation)
            let task = session.dataTask(with: request)
            box.attach(task)
            task.resume()
            continuation.onTermination = { _ in box.stop() }
        }
        return RemoteByteStream(bytes: bytes, abandon: { box.stop() })
    }
}
