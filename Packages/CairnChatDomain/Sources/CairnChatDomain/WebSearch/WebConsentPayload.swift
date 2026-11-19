import Foundation

/// What a web tool is about to send, stated so a consent sheet can name it.
///
/// The two web tools leave different things behind, and a sheet that said "something may go out" for both
/// would be worth nothing. A search sends the user's own words to a provider they picked; a page read sends
/// an address that provider was never involved in choosing. Same consent record, different sentence — which
/// is why the payload travels beside the provider rather than replacing it.
public enum WebConsentPayload: Sendable, Equatable {
    /// A search query, about to go to the named provider.
    case searchQuery
    /// A page address, about to be fetched. The host is named because it is the one fact about the target
    /// that is worth reading before agreeing; the path is not, and repeating it would put the user's
    /// browsing into a view that is supposed to be about permission.
    case fetchTarget(host: String)

    /// Whether this payload is the user's own words rather than an address they were handed.
    public var isQuery: Bool {
        if case .searchQuery = self { return true }
        return false
    }
}

/// The outbound badge's rule, as one pure function over the active provider row.
///
/// **Earlier than a receipt.** The badge used to appear only once a turn had used a tool, which is the last
/// moment a notice can be read — the query had already gone. The rule is now "the web tools are enabled and
/// the provider the user selected is somewhere beyond their own network", which is true the moment both are
/// true, and is exactly the condition a user would want to have noticed beforehand.
///
/// Both halves are needed. Enabling web tools without a public provider means nothing leaves; a public
/// provider inside a chat with no tools armed means nothing is being offered to a model either.
public enum WebSearchBadgeRule {
    /// Whether the badge stands up now, before anything has been sent.
    public static func showsImmediately(
        profile: WebSearchProviderProfile,
        webToolsEnabled: Bool
    ) -> Bool {
        webToolsEnabled && profile.reachesPublicInternet
    }

    /// The line beside the badge, naming where queries go rather than naming the tool that carried them.
    /// "Web tools sent data out" describes a past event; this describes the standing condition, which is
    /// the thing a user can still act on.
    public static func detail(profile: WebSearchProviderProfile) -> String {
        switch profile.kind {
        case .duckDuckGo: return "Search goes to DuckDuckGo"
        case .ollamaCloud: return "Search goes to Ollama Cloud"
        case .searxng: return "Search goes to \(profile.displayName)"
        }
    }
}
