import Foundation
import XCTest
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
        // The lock is taken in a synchronous helper, because `NSLock` cannot be held across an await.
        let (answer, failure) = record(request, byteLimit: byteLimit)
        if let failure { throw failure }
        return answer
    }

    /// The recording half. Kept synchronous on purpose: it is what the async `send` hands the locked
    /// part to, so nothing is ever held while the task is suspended.
    private func record(_ request: URLRequest, byteLimit: Int) -> (WebHTTPResponse, (any Error)?) {
        lock.lock()
        defer { lock.unlock() }
        sent.append(request)
        limits.append(byteLimit)
        return (canned, issue)
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

/// A search route stated as a value, so a test says which provider it means instead of reaching for a
/// Keychain to imply one.
///
/// Rows are placed directly rather than through `store.add`: these tests are about what the tool does with
/// a row, not about what the settings screen is allowed to save, and a cloud row is not user-addable by
/// design. The domain suite owns the validation rules.
///
/// `consent` is the state of the prompt rather than a second state type — the same row, differing only in
/// what the user answered. The default is a row already agreed to, because most tests are about what a
/// provider sends and reads. A row on the user's own network reports `.granted` whatever is passed here,
/// because it is not a third party.
func searchState(
    _ profile: WebSearchProviderProfile = .builtIn,
    credential: String? = nil,
    consent: WebSearchConsentState.Decision? = .granted,
    resultCount: Int = WebSearchProviderProfile.defaultResultCount
) -> WebSearchState {
    var settings = WebSearchSettings(
        providers: WebSearchProviderStore(providers: [profile], activeProviderID: profile.id),
        resultCount: resultCount
    )
    switch consent {
    case .granted: settings.consent.grant(profile)
    case .denied: settings.consent.deny(profile)
    case .undecided, nil: break
    }
    return WebSearchState(settings: settings, credential: credential)
}

/// A SearXNG row on the documented example LAN address.
func lanRow(name: String = "Box") -> WebSearchProviderProfile {
    WebSearchProviderProfile(
        kind: .searxng, displayName: name, baseURLString: "http://192.168.1.20:8888"
    )
}

/// A cloud row, mirroring a profile whose key the caller supplies separately.
func cloudRow(name: String = "Cloud") -> WebSearchProviderProfile {
    WebSearchProviderProfile(
        kind: .ollamaCloud, sourceProfileID: UUID(), displayName: name,
        baseURLString: WebSearchProviderKind.ollamaCloudEndpoint,
        credentialShape: .bearer, hasCredential: true
    )
}
