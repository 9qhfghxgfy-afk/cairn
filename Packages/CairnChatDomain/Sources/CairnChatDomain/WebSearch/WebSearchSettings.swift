import Foundation

/// The web-search settings, as one persisted value.
///
/// Three things belong together here and none of them is a secret: which providers exist, which one is
/// active, and what the user has agreed to send where. The result count is **app-wide rather than
/// per-provider** on purpose — it is how many results *Cairn* puts in front of the model, which is a
/// question about this app's prompt budget, not a property of the backend. Per-provider tuning would let a
/// user set ten results on a 4k-context model and then wonder why the answer forgot the question.
public struct WebSearchSettings: Sendable, Equatable, Codable {
    public var providers: WebSearchProviderStore
    public var resultCount: Int
    public var consent: WebSearchConsentState

    public init(
        providers: WebSearchProviderStore = .default,
        resultCount: Int = WebSearchProviderProfile.defaultResultCount,
        consent: WebSearchConsentState = .default
    ) {
        self.providers = providers
        self.resultCount = WebSearchProviderValidator.normalizedResultCount(resultCount)
        self.consent = consent
    }

    /// A fresh install: one provider, DuckDuckGo, active; nothing agreed to yet, because the first search
    /// is what asks.
    public static let `default` = WebSearchSettings()

    public var activeProvider: WebSearchProviderProfile { providers.active }

    /// Every row in list order, so a view or a test never has to reach through `providers.providers` to
    /// draw the list. The store owns the ordering rule; this only exposes it.
    public var allProviders: [WebSearchProviderProfile] { providers.providers }

    public var providerCount: Int { providers.providers.count }

    /// The condition the outbound badge is now keyed to: web tools are on **and** the active provider is
    /// somewhere beyond the user's own network. This is earlier than waiting for a turn to use a tool, and
    /// it is the whole point — a badge that appears only after the query has gone is a receipt, not a
    /// notice.
    public var activeProviderReachesPublicInternet: Bool { providers.active.reachesPublicInternet }

    public var revertNotice: WebSearchRevertNotice? { providers.revertNotice }

    public func consentDecision(for profile: WebSearchProviderProfile) -> WebSearchConsentState.Decision {
        consent.decision(for: profile)
    }

    /// Whether the next search has to be asked about first.
    public var requiresConsentPrompt: Bool {
        consent.requiresPrompt(for: providers.active)
    }

    public func setResultCount(_ count: Int) -> WebSearchSettings {
        var copy = self
        copy.resultCount = WebSearchProviderValidator.normalizedResultCount(count)
        return copy
    }
}

public extension AppSettings {
    /// The shipped answer when nothing is stored: DuckDuckGo active, five results, nothing consented.
    var webSearch: WebSearchSettings { webTools?.search ?? .default }

    var activeWebSearchProvider: WebSearchProviderProfile { webSearch.activeProvider }

    mutating func setWebSearch(_ settings: WebSearchSettings) {
        var updated = webTools ?? .default
        updated.search = settings
        webTools = updated
    }

    /// Selecting a provider is the one write most likely to come from a tap, so it goes through here rather
    /// than handing the whole store to the view.
    mutating func selectWebSearchProvider(id: UUID) {
        var search = webSearch
        search.providers.select(id: id)
        setWebSearch(search)
    }

    mutating func setWebSearchResultCount(_ count: Int) {
        setWebSearch(webSearch.setResultCount(count))
    }

    mutating func grantWebSearchConsent(for profile: WebSearchProviderProfile) {
        var search = webSearch
        search.consent.grant(profile)
        setWebSearch(search)
    }

    mutating func denyWebSearchConsent(for profile: WebSearchProviderProfile) {
        var search = webSearch
        search.consent.deny(profile)
        setWebSearch(search)
    }
}
