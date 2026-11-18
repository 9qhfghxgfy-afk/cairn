import Foundation
import CairnChatDomain

/// The keyless default: `GET https://html.duckduckgo.com/html/?q=…`.
///
/// Chosen because it needs no key, no account and no setup, which is what makes a search work on a
/// fresh install. It is also the one route that sends the user's query to a service the user never
/// picked, so the route is named in the tool's output and in the disclosure — never presented as
/// though it were private.
struct KeylessSearch: WebSearchProvider {
    static let endpointURL = "https://html.duckduckgo.com/html/"

    var route: WebSearchRoute { .keyless }

    var redirectAllowed: @Sendable (URL?) -> Bool { WebFetchGuard.allowsPublicHTTPS }

    func request(for query: String, limit: Int) -> URLRequest? {
        let text = WebSearchParsing.clean(query)
        guard !text.isEmpty, var components = URLComponents(string: Self.endpointURL) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        guard let url = components.url else { return nil }
        return WebFetchGuard.request(for: url, accept: "text/html")
    }

    func results(from response: WebHTTPResponse, limit: Int) -> [WebSearchResult] {
        guard response.looksLikeHTML, let html = String(data: response.data, encoding: .utf8) else {
            return []
        }
        return DuckDuckGoHTML.results(in: html, limit: limit)
    }
}
