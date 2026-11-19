import Foundation

/// What a provider's row says about who is on the other end of the request.
///
/// Attribution is not decoration. With DuckDuckGo active, the fact worth knowing is that the query went
/// to a company the user did not sign up with, and that Cairn speaks for itself and not for DuckDuckGo.
/// With a self-hosted instance the honest note is the opposite: there is nobody else. A note is shown
/// wherever the provider is named, and the wording is short enough to sit under a row.
public enum WebSearchAttribution {
    /// Shown beside the DuckDuckGo row and in the first-use disclosure. Cairn's own words; no DuckDuckGo
    /// art, mark or wording is reproduced.
    public static let duckDuckGoNote =
        "Results come from DuckDuckGo. Cairn is not affiliated with DuckDuckGo."

    /// The cloud route is billed and authenticated as the user, so it is named as theirs.
    public static let ollamaCloudNote =
        "Search runs through your Ollama Cloud profile and is billed by Ollama."

    /// A per-kind note, or nil when there is no third party to name.
    public static func note(for kind: WebSearchProviderKind) -> String? {
        switch kind {
        case .duckDuckGo: return duckDuckGoNote
        case .ollamaCloud: return ollamaCloudNote
        case .searxng: return nil
        }
    }

    /// The line a consent sheet puts under the provider's name: what actually leaves, in the same terms
    /// for every kind, because "the query" is the whole of it and saying more would be theatre.
    public static func disclosure(for kind: WebSearchProviderKind) -> String {
        switch kind {
        case .duckDuckGo:
            return "Only your search text goes out, as one request to DuckDuckGo. No chat text, no "
                + "attachments, no cookies kept."
        case .searxng:
            return "Only your search text goes out, to the instance you named. Nothing else from this "
                + "conversation travels with it."
        case .ollamaCloud:
            return "Only your search text goes out, to Ollama Cloud, authenticated as your profile."
        }
    }
}
