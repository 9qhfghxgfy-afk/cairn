import Foundation
import CairnChatDomain

/// Ollama Cloud search: `POST https://ollama.com/api/web_search`.
///
/// A **separate endpoint from chat**, with its own key: a cloud profile does not get search for free, it
/// gets search once the user has handed that profile a key. The provider row for it is materialised from
/// the profile and removed with it, so this kind is never added or deleted by hand.
///
/// The body is deliberately the smallest thing that can express the request:
///
///     {"query": "…", "max_results": n}
///
/// Those two keys and nothing else. A search request that carried any part of the conversation would make
/// this tool the widest leak in the app, so the tests assert the key set rather than trusting the comment.
///
/// **Real-network unverified.** The response field names are read defensively because the hosted endpoint
/// has not been exercised from this machine, and the rule is the one the other providers follow: an answer
/// that cannot be read is a named failure, never an invented result and never "no results".
struct OllamaCloudSearch: WebSearchProvider {
    let profile: WebSearchProviderProfile

    var byteLimit: Int { 96_000 }

    var redirectAllowed: @Sendable (URL?) -> Bool { WebFetchGuard.allowsPublicHTTPS }

    func dispatch(for query: String, limit: Int, credential: String?) -> WebSearchDispatch {
        let text = WebSearchParsing.clean(query)
        guard !text.isEmpty, let url = profile.endpoint else { return .failure(.invalidEndpoint) }
        if let failure = WebSearchRequests.failureForUnusable(url) { return .failure(failure) }
        let body: [String: JSONValue] = [
            "query": .text(text),
            "max_results": .integer(WebSearchProviderValidator.normalizedResultCount(limit)),
        ]
        guard let data = JSONValue.dictionary(body).encoded else {
            return .failure(.invalidEndpoint)
        }
        var request = WebFetchGuard.postRequest(for: url, body: data)
        // The token goes on through the shared rule, which is also what reports `providerUnavailable` when
        // the profile's key has been removed while its row was still selected.
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
        guard let entries = WebSearchParsing.resultArrays(in: document) else {
            return .failure(.unrecognizedResponse)
        }
        let found = WebSearchParsing.results(entries, limit: limit)
        return found.isEmpty ? .empty : .results(found)
    }
}
