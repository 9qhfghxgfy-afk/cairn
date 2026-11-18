import Foundation
import CairnChatDomain

/// Ollama's hosted web search: `POST https://ollama.com/api/web_search`.
///
/// This is a **separate API from the chat endpoint** and it needs the profile's own key — a cloud
/// profile does not get search for free, it gets search once the user has handed it a key. The body is
/// deliberately the smallest thing that can express the request:
///
///     {"query": "…", "max_results": n}
///
/// Those two keys and nothing else. A search request that carried any part of the conversation would
/// make the tool the widest leak in the app, so `WebSearchToolTests` asserts the key set rather than
/// trusting the comment above.
///
/// **Real-network unverified.** The response field names are read defensively because the hosted
/// endpoint has not been exercised from this machine; an answer that parses as no results is reported
/// as a failed search, never as an invented one.
struct OllamaCloudSearch: WebSearchProvider {
    static let endpointURL = "https://ollama.com/api/web_search"

    let token: String

    var route: WebSearchRoute { .ollamaCloud }

    func request(for query: String, limit: Int) -> URLRequest? {
        let text = WebSearchParsing.clean(query)
        guard !text.isEmpty, !token.isEmpty, let url = URL(string: Self.endpointURL) else { return nil }
        let body: [String: JSONValue] = [
            "query": .text(text),
            "max_results": .integer(min(max(1, limit), 10)),
        ]
        guard let data = JSONValue.dictionary(body).encoded else { return nil }
        return WebFetchGuard.postRequest(for: url, body: data, bearer: token)
    }

    func results(from response: WebHTTPResponse, limit: Int) -> [WebSearchResult] {
        WebSearchParsing.results(
            WebSearchParsing.resultArrays(in: WebSearchParsing.document(from: response)),
            limit: limit
        )
    }
}
