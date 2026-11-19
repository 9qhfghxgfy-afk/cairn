import Foundation
import CairnChatDomain

/// A SearXNG instance the user runs: `GET /search?format=json&q=…`.
///
/// This is the provider that removes the third party from the request, which is why it is the one row a
/// person is expected to configure by hand and why several can exist at once — a box at home and a friend's
/// instance are different answers to different questions. Plain `http://` is allowed for a private address
/// for the same reason a LAN inference server is allowed: the classifier says the host is private, Apple's
/// transport security applies only to public host names and protects nothing here, and only the user's own
/// network can see the request. A public address must be https.
///
/// **`format=json` is the whole fragility of this provider.** A SearXNG operator has to enable JSON output
/// in `settings.yml`; without it the instance answers with HTML, and a client that reads that HTML as
/// results is guessing. So a non-JSON reply is `unrecognizedResponse` with a hint about the setting, and
/// never a page of markup dressed up as sources.
struct SearxngSearch: WebSearchProvider {
    let profile: WebSearchProviderProfile

    var byteLimit: Int { 96_000 }

    /// The instance's own host, so a redirect may stay on it and go nowhere else.
    var redirectAllowed: @Sendable (URL?) -> Bool {
        let expected = profile.host.isEmpty ? nil : profile.host
        return { url in
            guard let expected, let actual = url?.host?.lowercased() else { return false }
            return actual == expected
        }
    }

    func dispatch(for query: String, limit: Int, credential: String?) -> WebSearchDispatch {
        guard let url = requestURL(for: WebSearchParsing.clean(query)) else {
            return .failure(.invalidEndpoint)
        }
        if let failure = WebSearchRequests.failureForUnusable(url) { return .failure(failure) }
        var request = WebFetchGuard.request(for: url, accept: "application/json")
        if let failure = WebSearchRequests.apply(credential: credential, to: &request, profile: profile) {
            return .failure(failure)
        }
        return .request(request, byteLimit: byteLimit)
    }

    func read(_ response: WebHTTPResponse, limit: Int) -> WebSearchRead {
        guard response.looksLikeJSON else { return .failure(.unrecognizedResponse) }
        guard let document = WebSearchParsing.document(from: response) else {
            return .failure(.decodeFailed)
        }
        if SearxngReply.enginesWereUnresponsive(document) { return .failure(.enginesUnavailable) }
        guard let entries = WebSearchParsing.resultArrays(in: document) else {
            return .failure(.unrecognizedResponse)
        }
        let found = WebSearchParsing.results(entries, limit: limit)
        return found.isEmpty ? .empty : .results(found)
    }

    /// The instance's search path plus the row's own parameters.
    ///
    /// The path is left alone when the operator put the instance under a reverse-proxy subpath — that is
    /// the common way a SearXNG box is exposed behind a tunnel, and rewriting `/searxng` to `/search` would
    /// break exactly those installs.
    private func requestURL(for text: String) -> URL? {
        guard !text.isEmpty, var components = URLComponents(string: profile.baseURLString) else {
            return nil
        }
        if components.path.isEmpty || components.path == "/" { components.path = "/search" }
        var items = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "safesearch", value: String(profile.safeSearch.wireValue)),
        ]
        if !profile.categories.isEmpty {
            items.append(URLQueryItem(name: "categories", value: profile.categories.joined(separator: ",")))
        }
        if let language = profile.language, !language.isEmpty {
            items.append(URLQueryItem(name: "language", value: language))
        }
        if let range = profile.timeRange {
            items.append(URLQueryItem(name: "time_range", value: range.searxngValue))
        }
        components.queryItems = items
        return components.url
    }
}

/// Telling the two empty answers SearXNG gives apart.
///
/// An instance whose upstream engines all timed out replies `200` with an empty or absent `results` array
/// and something in `error`/`unresponsive`. That is not "the web has nothing about this" — it is the
/// instance being down, and reporting it as no results sends the user away with a false conclusion.
enum SearxngReply {
    static func enginesWereUnresponsive(_ document: JSONValue) -> Bool {
        guard let fields = document.dictionaryValue else { return false }
        if case .array(let entries)? = fields["unresponsive"], !entries.isEmpty {
            // `results` missing or empty alongside a list of dead engines: the instance reached nobody.
            let hasResults = WebSearchParsing.resultArrays(in: document)?.isEmpty == false
            return !hasResults
        }
        guard let message = fields["error"]?.coercedText?.lowercased() else { return false }
        return message.contains("engine") && WebSearchParsing.resultArrays(in: document)?.isEmpty != false
    }
}
