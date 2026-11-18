import Foundation
import CairnChatDomain

/// One capped response a web tool got back, with the status kept rather than thrown.
///
/// A non-2xx is a *result* here, not an exception: "the search endpoint said no" has to come back to
/// the model as a typed tool failure it can act on, and a thrown transport error would end the whole
/// turn instead of one call.
struct WebHTTPResponse: Sendable {
    var status: Int
    var data: Data
    var mimeType: String?
    /// The address the body actually arrived from, after whatever redirects the policy allowed.
    var finalURL: URL?

    var succeeded: Bool { (200..<300).contains(status) }
    var looksLikeHTML: Bool {
        guard let mimeType else { return data.prefix(512).contains(Data("<html".utf8)) }
        return mimeType.lowercased().contains("html")
    }
    var looksLikeJSON: Bool {
        guard let mimeType else { return data.first == UInt8(ascii: "{") }
        return mimeType.lowercased().contains("json")
    }
}

/// The seam every web tool calls, so each one is testable with no socket in the room.
protocol WebRequesting: Sendable {
    /// Fetches with the body capped **while it arrives**, so a 40 MB page is stopped mid-download
    /// rather than read in full and then thrown away.
    ///
    /// The redirect test arrives per call rather than living in the transport, because the answer is a
    /// property of the request: a fetch of a public page may only hop to another public page, while a
    /// call to the user's own search instance may only stay on that host.
    func send(
        _ request: URLRequest,
        byteLimit: Int,
        redirectAllowed: @Sendable (URL?) -> Bool
    ) async throws -> WebHTTPResponse
}

extension WebRequesting {
    /// The conservative call: refuse every redirect. Anything that needs to follow a hop has to say
    /// what it will allow, so the unsafe default is the one you get by forgetting to specify.
    func send(_ request: URLRequest, byteLimit: Int) async throws -> WebHTTPResponse {
        try await send(request, byteLimit: byteLimit, redirectAllowed: { _ in false })
    }
}

/// The URLSession side of that seam.
///
/// Cookies are off in both directions and no shared header config is inherited: a search result must
/// not become a tracking identifier, and nothing this app fetches from a public service may be tied
/// back to a session. Redirects are decided one hop at a time by the caller's policy, because a
/// public host that answers with a `Location:` pointing at the user's LAN is exactly how a fetch tool
/// gets tricked into reading a private network.
struct WebHTTPTransport: WebRequesting {
    var timeout: TimeInterval
    var redirectLimit: Int

    init(timeout: TimeInterval = 15, redirectLimit: Int = 3) {
        self.timeout = timeout
        self.redirectLimit = redirectLimit
    }

    func send(
        _ request: URLRequest,
        byteLimit: Int,
        redirectAllowed: @Sendable (URL?) -> Bool
    ) async throws -> WebHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpShouldUsePipelining = false
        configuration.httpAdditionalHeaders = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = true

        let delegate = WebLoadDelegate(
            byteLimit: byteLimit, redirectLimit: redirectLimit, redirectAllowed: redirectAllowed
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        do {
            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.bind(continuation)
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
            session.finishTasksAndInvalidate()
            return response
        } catch {
            session.invalidateAndCancel()
            throw error
        }
    }
}
