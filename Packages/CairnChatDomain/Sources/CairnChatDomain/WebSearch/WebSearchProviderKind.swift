import Foundation

/// The kinds of search backend Cairn can be pointed at.
///
/// Three, for three different reasons. **DuckDuckGo** is the built-in default: it needs no key, no
/// account and no setup, so a fresh install can search without asking the user to run anything.
/// **SearXNG** is the self-hosted answer, and the strongest privacy choice available, because an
/// instance the user runs removes the third party from the request entirely. **Ollama Cloud search** is
/// a separate paid-side endpoint (`POST https://ollama.com/api/web_search`) that needs a key, so it is
/// offered only while such a key exists — it is never hand-added and never silently substituted.
///
/// Nothing here decides precedence. Exactly one provider is active at a time and a failing provider
/// produces a typed error, never a different provider.
public enum WebSearchProviderKind: String, Sendable, Equatable, Codable, CaseIterable {
    case duckDuckGo
    case searxng
    case ollamaCloud

    /// The built-in endpoint. HTML rather than a API: DuckDuckGo's JSON API is a different product with
    /// its own key, and the HTML endpoint is the one a plain client may use.
    public static let duckDuckGoEndpoint = "https://html.duckduckgo.com/html/"

    /// Ollama's hosted search. A different host path from chat, which is why a cloud chat profile does
    /// not get search "for free" — it gets search when the user hands the profile a key.
    public static let ollamaCloudEndpoint = "https://ollama.com/api/web_search"

    public var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .searxng: return "SearXNG"
        case .ollamaCloud: return "Ollama Cloud search"
        }
    }

    /// The row that always exists and can never be deleted, so there is never a build with no way to
    /// search and no way back when a self-hosted instance breaks.
    public var isBuiltIn: Bool { self == .duckDuckGo }

    /// Only SearXNG rows are added by hand. DuckDuckGo is already there, and Ollama Cloud search is
    /// materialised from the cloud profile that carries its key.
    public var isUserAddable: Bool { self == .searxng }

    /// Whether this kind cannot work without a Keychain-held secret.
    public var requiresCredential: Bool { self == .ollamaCloud }

    /// The host a fixed-endpoint kind must be sent to, or nil for a kind the user addresses themselves.
    public var fixedEndpoint: String? {
        switch self {
        case .duckDuckGo: return Self.duckDuckGoEndpoint
        case .ollamaCloud: return Self.ollamaCloudEndpoint
        case .searxng: return nil
        }
    }

    /// What the row's sub-label says about setup, so the difference between the three is visible
    /// without opening an editor.
    public var setupHint: String {
        switch self {
        case .duckDuckGo:
            return "Built in. No key, no account. Your query goes to DuckDuckGo."
        case .searxng:
            return "An instance you run. Nothing leaves unless you point it somewhere."
        case .ollamaCloud:
            return "Follows your Ollama Cloud profile and its key. Appears on its own."
        }
    }
}
