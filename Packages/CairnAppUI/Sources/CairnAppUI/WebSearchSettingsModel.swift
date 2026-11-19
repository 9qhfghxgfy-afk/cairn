import Foundation
import Observation
import CairnChatDomain

/// The view model behind the Web Search screen.
///
/// It exists for the same reason `ServersModel` does: a settings screen may not reach for a Keychain or a
/// socket, and `CairnAppUI` may not import the module that owns either. Everything the screen does goes
/// through here, and the two things it cannot do itself — read a secret, open a connection — arrive as
/// injected seams the App layer fills in.
///
/// Two vaults, and the split is the security model. `searchSecrets` holds a SearXNG row's own credential in
/// `app.cairn.websearch`; `serverSecrets` holds the token of the server profile a cloud row mirrors. A cloud
/// row is handed only its own profile's key, a SearXNG row is handed only the search vault, and the built-in
/// row is handed nothing at all. Passing one vault for both would let a search query carry a model server's
/// bearer token out to a search endpoint.
@Observable @MainActor
public final class WebSearchSettingsModel {
    /// Module-internal rather than `private`: `+Writes.swift` extends this type from another file. Views
    /// read through the computed properties below, not through this.
    let theme: ThemeModel
    let searchSecrets: (any SecretStoring)?
    let serverSecrets: (any SecretStoring)?
    /// The connection tester, behind a domain protocol so this module never names `URLSession`. nil means
    /// this build offers no Test Connection button rather than a button that cannot answer.
    let testing: (any WebSearchConnectionTesting)?

    /// The last Test Connection answer, kept per row so testing one row cannot rewrite the line under
    /// another one.
    public private(set) var testStatuses: [UUID: WebSearchTestStatus] = [:]
    public private(set) var isTestingID: UUID?
    /// Validation and storage problems, in the domain's own words. Never an address, never a token.
    public var lastError: String?

    public init(
        theme: ThemeModel,
        searchSecrets: (any SecretStoring)? = nil,
        serverSecrets: (any SecretStoring)? = nil,
        testing: (any WebSearchConnectionTesting)? = nil
    ) {
        self.theme = theme
        self.searchSecrets = searchSecrets
        self.serverSecrets = serverSecrets
        self.testing = testing
    }

    public var search: WebSearchSettings { theme.settings.webSearch }

    /// Every row in list order — the built-in row first, because it is the row the list is anchored to.
    public var rows: [WebSearchProviderProfile] { search.allProviders }

    public var active: WebSearchProviderProfile { search.activeProvider }

    public var resultCount: Int { search.resultCount }

    public static var resultCountRange: ClosedRange<Int> { WebSearchProviderProfile.resultCountRange }

    /// The sentence saying selection moved on its own, or nil when it did not. It stays until it is
    /// dismissed: search is about to go somewhere the user did not pick, and results from DuckDuckGo look
    /// exactly like results from anything else.
    public var revertNoticeText: String? { search.revertNotice?.text }

    /// The immediate badge: web tools are on **and** the active provider is beyond the user's own network.
    /// Earlier than a receipt, which is the whole point — a badge that appears after the query has gone is a
    /// record of what happened, not a notice.
    public var badgeShowsImmediately: Bool {
        WebSearchBadgeRule.showsImmediately(
            profile: active, webToolsEnabled: theme.settings.outboundWebAllowed
        )
    }

    public var badgeDetail: String { WebSearchBadgeRule.detail(profile: active) }

    /// What the consent record says about a row, so the screen can show "you allowed this" or "you said no"
    /// rather than leaving the user to discover it by searching.
    public func consent(for row: WebSearchProviderProfile) -> WebSearchConsentState.Decision {
        search.consentDecision(for: row)
    }

    /// Whether the next search through the active row has to be asked about first.
    public var willAskBeforeSearching: Bool { search.requiresConsentPrompt }

    /// The secret a row would search with, from whichever vault owns it.
    ///
    /// The kind decides the vault, so no call site can hand a SearXNG row a server's token or the reverse.
    /// Only the search vault is ever written from this screen.
    public func credential(for row: WebSearchProviderProfile) -> String? {
        guard row.credentialShape != nil else { return nil }
        switch row.kind {
        case .duckDuckGo: return nil
        case .ollamaCloud:
            guard let source = row.sourceProfileID else { return nil }
            return serverSecrets?.secret(for: source)
        case .searxng:
            return searchSecrets?.secret(for: row.id)
        }
    }

    public func select(id: UUID) {
        theme.selectWebSearchProvider(id: id)
        lastError = nil
    }

    /// The one count, applied to whichever provider is active. App-wide rather than per-row on purpose: it
    /// is how much Cairn puts in front of a model, which is a question about this app's prompt budget.
    public func setResultCount(_ count: Int) {
        theme.setWebSearchResultCount(count)
    }

    /// Clears the "selection moved" sentence once it has been read. Not cleared by a search succeeding —
    /// the change has to be acknowledged, not allowed to fade out underneath the user.
    public func dismissRevertNotice() {
        var search = theme.settings.webSearch
        search.providers.dismissRevertNotice()
        theme.setWebSearch(search)
    }
}
