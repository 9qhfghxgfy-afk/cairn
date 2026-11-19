import Foundation
import CairnChatDomain

/// Everything a search has to know, read at the moment of the call rather than captured when the
/// registry was built.
///
/// Two parts, and the split between them is the whole security model. `settings` is the provider list and
/// the selection — non-secret, and read from Settings so a search always uses the provider the user chose
/// *now*, not the one chosen at launch. `credential` is the one secret that call needs, read from the
/// Keychain at the moment of the call and held for nothing longer: never written to a settings row, never
/// placed in a tool result, never logged.
///
/// There is no route to compute any more. There is one active provider, and if it fails, the search fails.
public struct WebSearchState: Sendable {
    public var settings: WebSearchSettings
    /// The active provider's secret, or nil when it needs none.
    public var credential: String?

    public init(settings: WebSearchSettings = .default, credential: String? = nil) {
        self.settings = settings
        self.credential = credential
    }

    public var provider: WebSearchProviderProfile { settings.activeProvider }
    public var resultCount: Int { settings.resultCount }
    public var consent: WebSearchConsentState.Decision { settings.consentDecision(for: provider) }
}

/// Reads that state on the main actor, where Settings and the Keychain live. A closure rather than a
/// stored value, so a search sees what is true when it runs.
public typealias WebSearchStateReader = @MainActor @Sendable () -> WebSearchState
