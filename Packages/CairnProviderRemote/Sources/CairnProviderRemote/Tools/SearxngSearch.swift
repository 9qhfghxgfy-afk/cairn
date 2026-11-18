import Foundation
import CairnChatDomain

/// The user's own SearXNG instance: `GET /search?format=json&q=…`.
///
/// This is the one search route with no third party in the request at all, which is why the address
/// lives in Settings and why setting it changes the answer a search gives. Plain `http://` is allowed
/// for a private address for exactly the reason a LAN inference server is allowed: the classifier says
/// the host is private, Apple's ATS applies only to public host names and gives no protection to an IP
/// address, an unqualified name or a `.local` host, and only the user's own traffic can see that
/// request. A public address has to be https — the rule every other request in this app holds.
struct SearxngSearch: WebSearchProvider {
    let endpoint: String

    var route: WebSearchRoute { .searxng }

    /// The instance's own host, so a redirect may stay on it and go nowhere else.
    var host: String? { URLComponents(string: endpoint)?.host?.lowercased() }

    var redirectAllowed: @Sendable (URL?) -> Bool {
        let expected = host
        return { url in
            guard let expected, let actual = url?.host?.lowercased() else { return false }
            return actual == expected
        }
    }

    func request(for query: String, limit: Int) -> URLRequest? {
        let text = WebSearchParsing.clean(query)
        guard !text.isEmpty, var components = URLComponents(string: endpoint) else { return nil }
        if components.path.isEmpty || components.path == "/" { components.path = "/search" }
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components.url, isUsable(url) else { return nil }
        return WebFetchGuard.request(for: url, accept: "application/json")
    }

    func results(from response: WebHTTPResponse, limit: Int) -> [WebSearchResult] {
        WebSearchParsing.results(
            WebSearchParsing.resultArrays(in: WebSearchParsing.document(from: response)),
            limit: limit
        )
    }

    /// Usable means: no credentials in the URL, and either https anywhere or plain http to a private
    /// host. A public host over http is refused here rather than by the server.
    private func isUsable(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil,
              let scheme = url.scheme?.lowercased()
        else { return false }
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }
        return NetworkClassRouting.classify(host: host) != .publicInternet
    }
}
