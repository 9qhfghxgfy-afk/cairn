import Foundation
import CairnChatDomain

/// Per-request delegate behind `WebHTTPTransport`: caps the body as it arrives, judges every redirect
/// hop against the caller's policy, and never logs a URL, a header, or a byte of what it read.
///
/// Serialized on the session's own delegate queue; the lock guards only the handoff to the Swift task
/// that awaits the result, which is the same shape `RemoteBodyDelegate` uses for a chat stream.
final class WebLoadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let byteLimit: Int
    private let redirectLimit: Int
    private let redirectAllowed: @Sendable (URL?) -> Bool

    private let lock = NSLock()
    private var continuation: CheckedContinuation<WebHTTPResponse, any Error>?
    private var status: Int?
    private var mimeType: String?
    private var source: URL?
    private var body = Data()
    private var hops = 0
    private var overLimit = false
    private var isFinished = false

    init(
        byteLimit: Int,
        redirectLimit: Int,
        redirectAllowed: @escaping @Sendable (URL?) -> Bool
    ) {
        self.byteLimit = max(0, byteLimit)
        self.redirectLimit = max(0, redirectLimit)
        self.redirectAllowed = redirectAllowed
    }

    func bind(_ continuation: CheckedContinuation<WebHTTPResponse, any Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        lock.lock()
        status = http?.statusCode ?? 0
        mimeType = response.mimeType
        source = response.url ?? source
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        // One byte over the cap is enough to know: stop the download rather than buffer a page the
        // tool has already been told to refuse.
        if body.count + data.count > byteLimit {
            body.append(data.prefix(max(0, byteLimit - body.count)))
            overLimit = true
            lock.unlock()
            dataTask.cancel()
            return
        }
        body.append(data)
        lock.unlock()
    }

    /// A hop is allowed or refused here, one at a time. Refusal hands the 3xx response back as the
    /// result, so the tool reports a declined redirect rather than silently following it or inventing
    /// an answer.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        hops += 1
        let allowed = hops <= redirectLimit && redirectAllowed(request.url)
        lock.unlock()
        completionHandler(allowed ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let pending = continuation
        continuation = nil
        let settled = WebHTTPResponse(
            status: status ?? 0, data: body, mimeType: mimeType, finalURL: source ?? task.currentRequest?.url
        )
        let exceeded = overLimit
        lock.unlock()

        guard let sink = pending else { return }
        // The cap is reported ahead of the cancellation it caused: "too large" is the reason, and
        // "cancelled" would make it look as though the user stopped the turn.
        if exceeded {
            sink.resume(throwing: ToolFailure(.responseTooLarge))
            return
        }
        if let issue = error {
            let mapped = RemoteError.classify(issue)
            switch mapped {
            case .cancelled: sink.resume(throwing: CancellationError())
            case .timedOut: sink.resume(throwing: ToolFailure(.timedOut))
            default: sink.resume(throwing: mapped)
            }
            return
        }
        sink.resume(returning: settled)
    }
}
