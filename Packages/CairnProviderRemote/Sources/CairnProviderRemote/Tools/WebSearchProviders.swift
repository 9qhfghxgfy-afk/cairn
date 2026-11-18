import Foundation
import CairnChatDomain

/// Everything a search has to know to choose its route, read at the moment of the call rather than
/// captured when the registry was built.
///
/// The app layer builds this, because only the app can read Settings and the Keychain: a tool must not
/// own a settings store, and a search endpoint decision made from stale settings would send a query to
/// an address the user has since changed.
public struct WebSearchState: Sendable {
    public var routing: WebSearchRouting
    /// The kind of server this turn is running against, or nil when no server is selected.
    public var serverKind: ServerProfileKind?
    /// The active cloud profile's Keychain token, or nil when it has none.
    ///
    /// Held for the length of one call and nothing more: never written into a settings row, never
    /// placed in a tool result, never logged. Only its presence decides a route.
    public var cloudToken: String?

    public init(
        routing: WebSearchRouting = .default,
        serverKind: ServerProfileKind? = nil,
        cloudToken: String? = nil
    ) {
        self.routing = routing
        self.serverKind = serverKind
        self.cloudToken = cloudToken
    }

    public var route: WebSearchRoute { routing.route(forServerKind: serverKind) }
}

/// Reads that state on the main actor, where Settings and the Keychain live. A closure rather than a
/// stored value so a search always sees the server the user is on *now*.
public typealias WebSearchStateReader = @MainActor @Sendable () -> WebSearchState

/// One search endpoint: the request it would send, and the document it reads.
///
/// The request is *built* here and sent elsewhere, so "only the query leaves" is something a test can
/// read off one value instead of having to trust a socket.
protocol WebSearchProvider: Sendable {
    var route: WebSearchRoute { get }
    func request(for query: String, limit: Int) -> URLRequest?
    func results(from response: WebHTTPResponse, limit: Int) -> [WebSearchResult]
    /// Which redirect hops this endpoint may take. Declared by the provider, because the answer
    /// belongs to the endpoint: a public search service may only hop to another public address, and a
    /// self-hosted instance may only stay on its own host.
    var redirectAllowed: @Sendable (URL?) -> Bool { get }
}

extension WebSearchProvider {
    /// Default: follow nothing.
    var redirectAllowed: @Sendable (URL?) -> Bool { { _ in false } }
}

/// Reading the three documents these routes answer with down to one shape.
///
/// The names differ per endpoint (`results`, `items`, `organic`) and so do the fields
/// (`url`/`link`/`href`, `snippet`/`content`/`description`), which is why this looks for the first
/// field that exists rather than assuming one spelling. A snippet is only ever what the endpoint
/// itself published — Cairn does not summarise a page it has not read.
enum WebSearchParsing {
    /// A query as it may leave the device: trimmed, and bounded so one long model sentence cannot turn
    /// into one long query string in someone else's access log.
    static func clean(_ query: String) -> String {
        String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    static func document(from response: WebHTTPResponse) -> JSONValue? {
        JSONValue.decode(from: response.data)
    }

    static func resultArrays(in value: JSONValue?) -> [JSONValue] {
        guard let value else { return [] }
        for key in ["results", "items", "organic", "documents", "web"] {
            if case .array(let entries)? = value.dictionaryValue?[key] { return entries }
        }
        if case .array(let entries) = value { return entries }
        return []
    }

    static func results(_ entries: [JSONValue], limit: Int) -> [WebSearchResult] {
        entries.prefix(max(1, limit)).compactMap { entry in
            guard let fields = entry.dictionaryValue else { return nil }
            let url = firstText(fields, ["url", "link", "href", "absolute_url"]) ?? ""
            guard !url.isEmpty else { return nil }
            return WebSearchResult(
                title: firstText(fields, ["title", "name"]) ?? "",
                url: url,
                snippet: firstText(fields, ["snippet", "content", "description", "body"]) ?? ""
            )
        }
    }

    private static func firstText(_ fields: [String: JSONValue], _ names: [String]) -> String? {
        for name in names {
            if let text = fields[name]?.coercedText?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }
}
