import Foundation
import CairnChatDomain
@testable import CairnProviderRemote

/// The seam every web tool calls, replaced by a recorder. No socket is opened, so these suites pass
/// on a runner with no network at all — and the assertions land on the request that *would* have
/// left the device, which is the only place "only the query leaves" can actually be checked.
final class RecordingWebTransport: WebRequesting, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [URLRequest] = []
    private var limits: [Int] = []
    private var canned: WebHTTPResponse
    private var issue: (any Error)?

    init(reply: WebHTTPResponse = .json(#"{"results":[]}"#), throws error: (any Error)? = nil) {
        self.canned = reply
        self.issue = error
    }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return sent }
    var byteLimits: [Int] { lock.lock(); defer { lock.unlock() }; return limits }
    var requestCount: Int { requests.count }

    func send(
        _ request: URLRequest,
        byteLimit: Int,
        redirectAllowed: @escaping @Sendable (URL?) -> Bool
    ) async throws -> WebHTTPResponse {
        lock.lock()
        sent.append(request)
        limits.append(byteLimit)
        let answer = canned
        let failure = issue
        lock.unlock()
        if let failure { throw failure }
        return answer
    }
}

extension WebHTTPResponse {
    static func json(_ text: String, status: Int = 200, from url: URL? = nil) -> WebHTTPResponse {
        WebHTTPResponse(status: status, data: Data(text.utf8), mimeType: "application/json", finalURL: url)
    }

    static func html(_ text: String, status: Int = 200, from url: URL? = nil) -> WebHTTPResponse {
        WebHTTPResponse(status: status, data: Data(text.utf8), mimeType: "text/html", finalURL: url)
    }

    static func text(_ text: String, status: Int = 200, from url: URL? = nil) -> WebHTTPResponse {
        WebHTTPResponse(status: status, data: Data(text.utf8), mimeType: "text/plain", finalURL: url)
    }
}

/// Reading a built request back, so a privacy claim is asserted on the request rather than on a log.
enum RequestReader {
    static func queryItems(_ request: URLRequest) -> [String: String] {
        URLComponents(url: request.url ?? URL(string: "https://example.com")!,
                      resolvingAgainstBaseURL: false)?
            .queryItems?.reduce(into: [:]) { found, item in found[item.name] = item.value ?? "" } ?? [:]
    }

    static func bodyFields(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody, "the request carries no body")
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    static func header(_ request: URLRequest, _ field: String) -> String? {
        request.value(forHTTPHeaderField: field)
    }
}

/// A search route stated as a value, so a test says which route it means instead of reaching for a
/// Keychain to imply one.
func searchState(
    searxng: String? = nil, serverKind: ServerProfileKind? = nil, cloudToken: String? = nil
) -> WebSearchState {
    WebSearchState(
        routing: WebSearchRouting(searxngURL: searxng, hasOllamaCloudKey: cloudToken != nil),
        serverKind: serverKind, cloudToken: cloudToken
    )
}
