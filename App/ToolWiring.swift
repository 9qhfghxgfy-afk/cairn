import CairnAppUI
import CairnChatDomain
import CairnProviderRemote
import Foundation

/// Assembles the app's tool surface and installs it on the workspace.
///
/// Only this layer can build a registry. `compose_mail` needs a window, which lives in `CairnAppUI`;
/// search needs the endpoint and the acknowledgement from Settings; the cloud route needs the active
/// profile's Keychain-backed key, which lives in `CairnProviderRemote`. The pure domain reaches for none
/// of those, so the answer has to be injected — and the injection point is one file rather than four
/// call sites in `CairnApp`.
@MainActor
final class ToolWiring {
    private let settings: ThemeModel
    private let secrets: KeychainSecretStore
    private let servers: ServersModel?
    /// Held for the life of the app: the mail composer, and the delegate that composer calls back on. A
    /// presenter owned by a tool call would be released the moment that call returned, taking the sheet
    /// the user is still reading with it.
    private let mail = MailComposerPresentation()

    init(settings: ThemeModel, secrets: KeychainSecretStore, servers: ServersModel?) {
        self.settings = settings
        self.secrets = secrets
        self.servers = servers
    }

    /// What one search reads at the moment it runs: the settings as they are now, the server this chat
    /// is on now, and the key that server has now. Read lazily on purpose — a snapshot taken at launch
    /// would keep sending queries to an address the user has already changed.
    func searchState() -> WebSearchState {
        guard let profile = servers?.activeProfile() else {
            return WebSearchState(routing: settings.settings.routing())
        }
        // Only the cloud kind is asked for a key. A LAN profile's bearer token belongs to that server's
        // own API and has no business travelling to a search endpoint.
        let token = profile.kind == .ollamaCloud ? secrets.secret(for: profile.id) : nil
        return WebSearchState(
            routing: settings.settings.routing(hasOllamaCloudKey: token != nil),
            serverKind: profile.kind,
            cloudToken: token
        )
    }

    /// The registry as the settings stand right now: the on-device tools always, the three web tools
    /// only once the acknowledgement is up.
    func registry() -> ToolRegistry {
        BuiltInToolRegistry.make(
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
