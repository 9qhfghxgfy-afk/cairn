import CairnAppUI
import CairnChatDomain
import CairnProviderRemote
import Foundation

/// The web-search surface at the only layer that can hold it.
///
/// Three things meet here and nowhere else: the settings store and the two Keychain vaults
/// (`CairnPersistence`, `CairnProviderRemote`), and the screens (`CairnAppUI`). The domain and the UI each see
/// a seam — a settings value, a closure that answers Bool — and neither sees the other's business. That is what
/// keeps `CairnAppUI` from ever importing `URLSession`, and the pure domain from ever touching a vault.
///
/// The legacy single-SearXNG-address upgrade is **not** here, deliberately. The import belongs to the settings
/// record that holds the legacy column: `SettingsRecord.toSettings()` imports on the first read after an
/// upgrade and the next write stores the row, so there is no window in which an instance the user was already
/// searching through stops working. An app-launch import would run second, against an already-imported value,
/// and would be a second answer to one question.
///
/// What is here is the one decision neither module may make alone: **one sheet, two tools.** `web_search` and
/// `web_fetch` both stop and ask, and both are closed over the same consent model, so nobody is interrupted
/// twice for one decision. The answer is filed under the subject it was about — a provider row's grant, or the
/// single page-reading answer — because "I let my own instance see my queries" and "Cairn may read pages" are
/// different sentences, and a grant given to one provider must not be read as permission to read anywhere.
@MainActor
final class WebSearchWiring {
    /// The thing the consent sheet is drawn from, and the thing both web tools wait on.
    let consent: WebSearchConsentModel
    /// The Web Search screen's model: the rows, the vaults, and the tester.
    let settings: WebSearchSettingsModel

    private init(consent: WebSearchConsentModel, settings: WebSearchSettingsModel) {
        self.consent = consent
        self.settings = settings
    }

    /// Builds the surface.
    ///
    /// - Parameters:
    ///   - serverSecrets: the vault holding server-profile tokens. A cloud search row is handed only the key of
    ///     the profile it mirrors, and never anything else in here.
    ///   - searchSecrets: the search vault, `app.cairn.websearch`. A SearXNG row's token lives here and nowhere
    ///     else, which is what stops a search query from ever carrying a model server's bearer token.
    ///   - testing: the connection tester, behind the domain's own seam so the settings screen never names a
    ///     transport. A build that passes nil gets no Test button rather than a button that cannot answer.
    static func install(
        theme: ThemeModel,
        serverSecrets: any SecretStoring,
        searchSecrets: any SecretStoring = WebSearchKeychain.store(),
        testing: (any WebSearchConnectionTesting)? = WebSearchConnectionTester()
    ) -> WebSearchWiring {
        WebSearchWiring(
            consent: WebSearchConsentModel(theme: theme),
            settings: WebSearchSettingsModel(
                theme: theme,
                searchSecrets: searchSecrets,
                serverSecrets: serverSecrets,
                testing: testing
            )
        )
    }

    /// The seam `web_search` asks through: may this provider receive these words?
    ///
    /// A build that never installs a wiring object has no seam at all, and `WebSearchTool` treats that as a
    /// refusal rather than a free pass — see `WebSearchConsentGate`.
    var searchRequester: WebSearchConsentRequester {
        let model = consent
        return { profile in await model.allowSearch(provider: profile) }
    }

    /// The seam `web_fetch` asks through: may a page be read off this device?
    var fetchRequester: WebFetchConsentRequester {
        let model = consent
        return { url in await model.allowPageRead(url: url) }
    }
}
