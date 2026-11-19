import Foundation
import CairnChatDomain

/// Cairn's built-in provider: `GET https://html.duckduckgo.com/html/?q=…`.
///
/// This is the row a fresh install starts with, and the row selection falls back to. DuckDuckGo is offered
/// because it needs no key, no account and no setup — not because it is private. It is the one provider
/// that sends the user's query to a service the user never signed up with, so the provider is named in
/// every answer, the attribution says Cairn is not affiliated with it, and consent is asked per provider
/// rather than assumed from a general "web tools" switch.
///
/// The endpoint is the **HTML page, not an API**. Its JSON API is a different product with its own key and
/// its own terms; the HTML endpoint is what a plain client is expected to use. That also means the reply is
/// markup with class names rather than a documented schema, so parsing is best-effort and a page that no
/// longer matches is reported as `unrecognizedResponse` — never as "no results", which would be a lie about
/// what exists.
///
/// **Courtesy, honestly stated.** One request per search, a Cairn user agent, no cookie, no rotation, no
/// fingerprint evasion, and pacing in front of it (`WebSearchThrottle`). Results are shown to the person
/// who asked for them and are not republished at volume. If DuckDuckGo refuses, the refusal is reported as
/// `blocked` and Cairn does not retry or go somewhere else instead.
struct DuckDuckGoSearch: WebSearchProvider {
    let profile: WebSearchProviderProfile

    /// A results page is markup, not a payload: room for the page furniture, still capped.
    var byteLimit: Int { 160_000 }

    var redirectAllowed: @Sendable (URL?) -> Bool { WebFetchGuard.allowsPublicHTTPS }

    func dispatch(for query: String, limit: Int, credential: String?) -> WebSearchDispatch {
        guard let url = requestURL(for: WebSearchParsing.clean(query)) else {
            return .failure(.invalidEndpoint)
        }
        if let failure = WebSearchRequests.failureForUnusable(url) { return .failure(failure) }
        var request = WebFetchGuard.request(for: url, accept: "text/html")
        if let failure = WebSearchRequests.apply(credential: credential, to: &request, profile: profile) {
            return .failure(failure)
        }
        return .request(request, byteLimit: byteLimit)
    }

    /// The page address with the row's own choices on it.
    ///
    /// `q` and `safesearch` are the pair this endpoint documents. `df` is sent when a time range is set —
    /// DuckDuckGo's own time filter uses that parameter, and an endpoint that ignores an unknown one still
    /// answers, so it cannot corrupt a search. **Not re-verified from this machine**; the search still works
    /// if the parameter is ignored, which is why it is sent rather than gated.
    private func requestURL(for text: String) -> URL? {
        guard !text.isEmpty, var components = URLComponents(string: profile.baseURLString) else {
            return nil
        }
        var items = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "safesearch", value: String(profile.safeSearch.wireValue)),
        ]
        if let range = profile.timeRange {
            items.append(URLQueryItem(name: "df", value: range.duckDuckGoValue))
        }
        components.queryItems = items
        return components.url
    }

    func read(_ response: WebHTTPResponse, limit: Int) -> WebSearchRead {
        guard response.looksLikeHTML, let html = String(data: response.data, encoding: .utf8) else {
            return .failure(.unrecognizedResponse)
        }
        switch DuckDuckGoHTML.pageKind(in: html) {
        case .unrecognized: return .failure(.unrecognizedResponse)
        case .empty: return .empty
        case .challenge: return .failure(.blocked)
        case .results:
            let found = DuckDuckGoHTML.results(in: html, limit: limit)
            // Markers were there and nothing came of them: the page changed shape, which is a break, not
            // an empty answer.
            return found.isEmpty ? .failure(.unrecognizedResponse) : .results(found)
        }
    }
}
