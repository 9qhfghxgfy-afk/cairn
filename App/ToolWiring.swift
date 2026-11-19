import CairnAppUI
import CairnChatDomain
import CairnProviderRemote
import Foundation

/// Assembles the app's tool surface and installs it on the workspace.
///
/// Only this layer can build a registry. `compose_mail` needs a window, which lives in `CairnAppUI`; search
/// needs the provider list and the acknowledgement from Settings; a cloud provider row needs the server
/// profile's Keychain-backed key, which lives in `CairnProviderRemote`. The pure domain reaches for none of
/// those, so the answer has to be injected — and the injection point is one file rather than four call sites
/// in `CairnApp`.
@MainActor
final class ToolWiring {
    private let settings: ThemeModel
    private let secrets: KeychainSecretStore
    private let servers: ServersModel?
    /// Search credentials, in their own Keychain service. A SearXNG token is not a model server's token, and
    /// one vault for both would let a search row reach a server's bearer token by accident.
    private let searchSecrets: KeychainSecretStore
    /// Held for the life of the app: the mail composer, and the delegate that composer calls back on. A
    /// presenter owned by a tool call would be released the moment that call returned, taking the sheet the
    /// user is still reading with it.
    private let mail = MailComposerPresentation()

    init(
        settings: ThemeModel,
        secrets: KeychainSecretStore,
        servers: ServersModel?,
        searchSecrets: KeychainSecretStore = WebSearchKeychain.store()
    ) {
        self.settings = settings
        self.secrets = secrets
        self.servers = servers
        self.searchSecrets = searchSecrets
    }

    /// What one search reads at the moment it runs: the provider settings as they are now, and the one
    /// secret the active row needs. Read lazily on purpose — a snapshot taken at launch would keep sending
    /// queries to a provider the user has already changed.
    func searchState() -> WebSearchState {
        let search = settings.settings.webSearch
        return WebSearchState(settings: search, credential: credential(for: search.activeProvider))
    }

    /// The secret the active row uses, from whichever vault owns it.
    ///
    /// A cloud row mirrors a server profile, so its key is that profile's key in the server vault; a
    /// SearXNG row has its own credential in the search vault; the built-in row has none. No kind is ever
    /// handed the other kind's secret, which is the reason there are two vaults.
    private func credential(for profile: WebSearchProviderProfile) -> String? {
        guard profile.credentialShape != nil else { return nil }
        switch profile.kind {
        case .duckDuckGo:
            return nil
        case .ollamaCloud:
            guard let source = profile.sourceProfileID else { return nil }
            return secrets.secret(for: source)
        case .searxng:
            return searchSecrets.secret(for: profile.id)
        }
    }

    /// Keeps the Ollama Cloud rows matched to the profiles that carry a key.
    ///
    /// Reconciliation rather than events: this runs whenever the tool surface is assembled, a missed signal
    /// cannot leave a dead provider row behind, and running it twice changes nothing. It is what makes the
    /// cloud row appear on its own when a key is added, and vanish on its own when the key or the profile
    /// goes — with selection reverting to DuckDuckGo and a stored notice saying so.
    func syncCloudRows() {
        let mirrors = (servers?.profiles ?? []).compactMap { profile -> WebSearchCloudMirror? in
            guard profile.kind == .ollamaCloud else { return nil }
            return WebSearchCloudMirror(
                sourceProfileID: profile.id,
                profileName: profile.name,
                hasKey: secrets.secret(for: profile.id) != nil
            )
        }
        var search = settings.settings.webSearch
        var store = search.providers
        store.sync(cloudMirrors: mirrors)
        guard store != search.providers else { return }
        // Only the rows move here; the user's consent and result count stay exactly as they were.
        search.providers = store
        settings.setWebSearch(search)
    }

    /// The registry as the settings stand right now: the on-device tools always, the three web tools only
    /// once the acknowledgement is up.
    func registry() -> ToolRegistry {
        syncCloudRows()
        return BuiltInToolRegistry.make(
            searchState: { [self] in searchState() },
            mailPresenter: mail,
            webToolsAllowed: settings.settings.outboundWebAllowed
        )
    }

    /// Installs the tools on a workspace and on the session that is live at this moment.
    func install(on workspace: ChatWorkspace) {
        workspace.apply(
            tools: registry(),
            outboundWebAllowed: settings.settings.outboundWebAllowed,
            showsGenerationStats: settings.settings.showsGenerationStats
        )
    }
}
