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
    /// The order, and the reason for it: **the server you are already talking to goes first.** An
    /// Ollama Cloud profile holding a Keychain-backed key is a service the user chose for this
    /// conversation, so its own search endpoint is the one place a query goes that the user has
    /// already agreed to. Next comes a self-hosted SearXNG instance — the user's own machine, with no
    /// third party in the request at all — and last the keyless built-in default, which is the only
    /// route that sends a query to a service the user never picked. A cloud profile **without** a key
    /// falls through to the built-in default rather than failing, and the route that ran is named to
    /// the UI and to the model, so a fallback is never hidden.
    public func route(forServerKind kind: ServerProfileKind?) -> WebSearchRoute {
        if kind == .ollamaCloud && hasOllamaCloudKey { return .ollamaCloud }
        if searxngURL != nil { return .searxng }
        return .keyless
    }

    /// True when a search on this turn reaches something beyond this device, which is exactly the
    /// condition the outbound badge is for.
    public var leavesTheDevice: Bool { true }
}
