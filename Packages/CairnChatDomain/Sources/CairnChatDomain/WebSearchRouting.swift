import Foundation

/// Which search endpoint one turn's `web_search` goes to, decided from data rather than from a
/// guess about the server.
///
/// Three routes exist, and the finding that shapes them is that Ollama's hosted web search is a
/// **separate endpoint** (`POST https://ollama.com/api/web_search`) that requires an API key and an
/// account — so a cloud profile does not get search "for free", it gets search once the user hands
/// it a key. Everything else falls to the keyless default, and a user who runs their own SearXNG
/// instance always wins, because a self-hosted endpoint is the one answer that removes a third
/// party from the request entirely.
public enum WebSearchRoute: String, Sendable, Equatable, Codable, CaseIterable {
    /// Cairn's built-in endpoint. No key, no account, no setup.
    case keyless
    /// The user's own SearXNG instance.
    case searxng
    /// Ollama Cloud's own search endpoint, reachable only with the profile's key.
    case ollamaCloud

    public var label: String {
        switch self {
        case .keyless: return "built-in search"
        case .searxng: return "your SearXNG instance"
        case .ollamaCloud: return "Ollama Cloud search"
        }
    }

    /// What the disclosure has to say, which differs per route: only `.keyless` sends a query to a
    /// third-party service the user never configured.
    public var sendsQueryToThirdParty: Bool { self == .keyless }
}

public struct WebSearchRouting: Sendable, Equatable {
    /// A non-secret URL the user typed in Settings. Empty means "not set".
    public var searxngURL: String?
    /// True when the active Ollama Cloud profile has a Keychain-backed key. The key itself is never
    /// here — only whether one exists, so a decision can be made without reading the Keychain.
    public var hasOllamaCloudKey: Bool

    public init(searxngURL: String? = nil, hasOllamaCloudKey: Bool = false) {
        let trimmed = searxngURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.searxngURL = (trimmed?.isEmpty == false) ? trimmed : nil
        self.hasOllamaCloudKey = hasOllamaCloudKey
    }

    /// The shape a build with no settings wired has: the keyless default, and nothing else.
    public static let `default` = WebSearchRouting()

    /// The route for the server this turn is running against.
    ///
    /// Order matters, and it is a privacy order: a self-hosted instance beats the cloud's key-gated
    /// endpoint, and the cloud's endpoint beats sending a query to a service the user never chose.
    /// A cloud profile **without** a key falls back to the keyless default rather than failing —
    /// the tool still works, and the UI says which route ran so the fallback is not hidden.
    public func route(forServerKind kind: ServerProfileKind?) -> WebSearchRoute {
        if searxngURL != nil { return .searxng }
        if kind == .ollamaCloud && hasOllamaCloudKey { return .ollamaCloud }
        return .keyless
    }

    /// True when a search on this turn reaches something beyond this device, which is exactly the
    /// condition the outbound badge is for.
    public var leavesTheDevice: Bool { true }
}

/// One search result, in the shape every route reduces to.
///
/// The three routes answer in three different documents; normalising them here is what lets the
/// tool's output, the card, and the tests speak one format. `snippet` is what the endpoint itself
/// published — Cairn does not summarise a page it has not read.
public struct WebSearchResult: Sendable, Equatable, Codable {
    public var title: String
    public var url: String
    public var snippet: String

    public init(title: String, url: String, snippet: String = "") {
        self.title = title
        self.url = url
        self.snippet = snippet
    }

    public var isUsable: Bool { !url.isEmpty }

    /// The lines a model reads, numbered so it can cite one and hand its URL to `web_fetch`.
    public static func render(_ results: [WebSearchResult]) -> String {
        let usable = results.filter(\.isUsable)
        guard !usable.isEmpty else { return "" }
        return usable.enumerated().map { index, result in
            var line = "\(index + 1). \(result.title.isEmpty ? result.url : result.title)\n   \(result.url)"
            let snippet = result.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty { line += "\n   \(snippet)" }
            return line
        }.joined(separator: "\n\n")
    }
}
