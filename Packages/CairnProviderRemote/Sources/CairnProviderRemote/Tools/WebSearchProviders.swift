import Foundation
import CairnChatDomain

/// What asking a provider for a request produced: something to send, or the reason there is nothing to
/// send.
///
/// A failure at this stage is never generic. "That address needs a secure connection" and "this provider
/// has no credential" look alike from a socket's point of view and are completely different things for the
/// user to fix, so the reason travels as a value all the way to the card.
enum WebSearchDispatch {
    case request(URLRequest, byteLimit: Int)
    case failure(WebSearchFailure)
}

/// What reading a provider's reply produced.
///
/// `empty` and `failure` are separate cases because they mean different things to the model, and the old
/// code collapsed them into one — which is how a provider whose output format moved came to report that
/// nothing existed.
enum WebSearchRead {
    case results([WebSearchResult])
    case empty
    case failure(WebSearchFailure)
}

/// One search provider: the request it would send, and the document it reads back.
///
/// The request is *built* here and sent elsewhere, so "only the query leaves" is something a test can read
/// off one value instead of having to trust a socket.
protocol WebSearchProvider: Sendable {
    var profile: WebSearchProviderProfile { get }

    /// Builds the request, or names why this row cannot produce one.
    func dispatch(for query: String, limit: Int, credential: String?) -> WebSearchDispatch

    /// How much of the reply to accept. A page endpoint needs room for markup; an API endpoint does not.
    var byteLimit: Int { get }

    /// Which redirect hops this provider may take. Declared by the provider, because the answer belongs to
    /// the endpoint: a public search service may only hop to another public address, and a self-hosted
    /// instance may only stay on its own host.
    var redirectAllowed: @Sendable (URL?) -> Bool { get }

    /// Turns a reply into results, an honest empty, or a named failure. Never an empty list standing in
    /// for a break.
    func read(_ response: WebHTTPResponse, limit: Int) -> WebSearchRead
}

extension WebSearchProvider {
    /// The conservative defaults: follow nothing, and keep the reply small.
    var redirectAllowed: @Sendable (URL?) -> Bool { { _ in false } }
    var byteLimit: Int { 96_000 }
}

/// Reading the different documents providers answer with down to one shape.
///
/// The names differ per provider (`results`, `items`, `organic`) and so do the fields
/// (`url`/`link`/`href`, `snippet`/`content`/`description`), which is why this looks for the first field
/// that exists rather than assuming one spelling. A snippet is only ever what the provider itself
/// published — Cairn does not summarise a page it has not read.
enum WebSearchParsing {
    /// A query as it may leave the device: trimmed, and bounded so one long model sentence cannot turn
    /// into one long query string in someone else's access log.
    static func clean(_ query: String) -> String {
        String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    static func document(from response: WebHTTPResponse) -> JSONValue? {
        JSONValue.decode(from: response.data)
    }

    /// The entries array, wherever this provider keeps it — or **nil** when the document has no results
    /// section at all. nil is the distinction that matters: a document without a results section is a
    /// changed provider, and an empty array is a provider that found nothing.
    static func resultArrays(in value: JSONValue?) -> [JSONValue]? {
        guard let value else { return nil }
        if case .array(let entries) = value { return entries }
        guard let fields = value.dictionaryValue else { return nil }
        for key in ["results", "items", "organic", "documents", "web"] {
            if case .array(let entries)? = fields[key] { return entries }
        }
        return nil
    }

    /// Reads entries into results, dropping anything without an address and collapsing a URL that appears
    /// twice. A duplicate is not a second source, and a model that cites two of them has one source.
    static func results(_ entries: [JSONValue], limit: Int) -> [WebSearchResult] {
        var seen = Set<String>()
        var found: [WebSearchResult] = []
        for entry in entries {
            guard found.count < max(1, limit) else { break }
            guard let fields = entry.dictionaryValue else { continue }
            let url = firstText(fields, ["url", "link", "href", "absolute_url"]) ?? ""
            guard !url.isEmpty, !seen.contains(url) else { continue }
            seen.insert(url)
            found.append(WebSearchResult(
                title: firstText(fields, ["title", "name"]) ?? "",
                url: url,
                snippet: firstText(fields, ["snippet", "content", "description", "body"]) ?? ""
            ))
        }
        return found
    }

    static func firstText(_ fields: [String: JSONValue], _ names: [String]) -> String? {
        for name in names {
            if let text = fields[name]?.coercedText?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }
}
