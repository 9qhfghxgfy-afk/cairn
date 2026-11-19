import Foundation
import CairnChatDomain

/// A provider row turned into the thing that talks to it.
///
/// One switch, on purpose. The kind is what decides the request shape, so the mapping from a stored row to
/// a transport has to be exhaustive over `WebSearchProviderKind` — a new kind that forgets to appear here
/// fails at compile time rather than at search time.
enum WebSearchProviderFactory {
    static func make(profile: WebSearchProviderProfile) -> (any WebSearchProvider)? {
        switch profile.kind {
        case .duckDuckGo: return DuckDuckGoSearch(profile: profile)
        case .searxng: return SearxngSearch(profile: profile)
        case .ollamaCloud: return OllamaCloudSearch(profile: profile)
        }
    }
}
