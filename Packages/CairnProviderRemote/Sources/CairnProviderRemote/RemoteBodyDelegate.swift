import Foundation

/// Per-request URLSession delegate: forwards body bytes to a stream in arrival order,
/// turns a non-2xx status into a typed error, and never logs a URL, a header, or a body.
///
/// Serialized on the session's own delegate queue; the lock only guards the handoff to
/// the Swift task that consumes the stream.
final class RemoteBodyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Enough of an error body to report the server's own message, capped so a stray
    /// HTML error page cannot grow without bound.
    private static let errorBodyLimit = 16_384
    private static let errorSnippetChars = 240

    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
    private var statusCode: Int?
    private var errorBody = Data()
    private var isFinished = false

    func bind(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
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
        let status = (response as? HTTPURLResponse)?.statusCode
        lock.lock()
        statusCode = status
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let status = statusCode
        if let status, !(200..<300).contains(status) {
            if errorBody.count < Self.errorBodyLimit { errorBody.append(data) }
            lock.unlock()
            return
        }
        let sink = continuation
        lock.unlock()
        sink?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        if isFinished {
            lock.unlock()
            return
        }
        isFinished = true
        let status = statusCode
        let body = errorBody
        let sink = continuation
        continuation = nil
        lock.unlock()

        if let error {
            sink?.finish(throwing: RemoteError.classify(error))
            return
        }
        if let status, !(200..<300).contains(status) {
            sink?.finish(throwing: RemoteError.httpStatus(status, serverMessage: Self.serverMessage(in: body)))
            return
        }
        sink?.finish()
    }

    /// Pulls the operational message out of an error payload (`{"error": "..."}` for
    /// Ollama, `{"error": {"message": "..."}}` for OpenAI-compatible servers).
    static func serverMessage(in data: Data) -> String? {
        guard !data.isEmpty, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let candidates: [String?] = [
            (object["error"] as? String),
            ((object["error"] as? [String: Any])?["message"] as? String),
            (object["message"] as? String),
        ]
        guard let message = candidates.compactMap({ $0 }).first, !message.isEmpty else { return nil }
        return String(message.prefix(errorSnippetChars))
    }
}
