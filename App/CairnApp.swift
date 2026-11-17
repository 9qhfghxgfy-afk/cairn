import SwiftUI
import CairnAppUI
import CairnChatDomain
import CairnPersistence
import CairnProviderRemote

@main
struct CairnApp: App {
    var body: some Scene {
        WindowGroup {
            CairnLaunchView()
        }
    }
}

/// Builds the workspace once, keeping the persistent store and the memory-only store
/// as two separate objects so Temporary Chat can never write to disk by accident.
struct CairnLaunchView: View {
    @State private var workspace: ChatWorkspace?
    @State private var servers: ServersModel?
    @State private var theme: ThemeModel?
    @State private var startupFailure: String?

    var body: some View {
        Group {
            if let workspace {
                CairnRootView(workspace: workspace, servers: servers, settings: theme)
            } else if let startupFailure {
                ContentUnavailableView(
                    "Cairn could not open its local store",
                    systemImage: "exclamationmark.triangle",
                    description: Text(startupFailure)
                )
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            guard workspace == nil else { return }
            do {
                let persistent = try SwiftDataStore()
                let secrets = KeychainSecretStore()
                let factory = RemoteProviderFactory(secrets: secrets)
                // The registry is the live engine list: saving or disabling a profile changes
                // what the next turn can use, without rebuilding conversations. The mock stays
                // registered so the offline demo path keeps working on a fresh install.
                let registry = ProviderRegistry(providers: [MockStreamingProvider()])
                // Which server is in use, and what each server was last used with, is one shared
                // object. The Servers screen and every chat read and write it, so a tap in either
                // place is true in the other — and it is written through to disk, so it survives a
                // relaunch rather than being an instant switch that evaporates.
                let selection = ServerSelectionModel(storing: persistent)
                // One object for the theme, the appearance and the Default Configuration, because they
                // are one stored row: a default configuration saved without the theme beside it would
                // leave the app disagreeing with itself.
                let builtTheme = ThemeModel(storing: persistent)
                let builtWorkspace = ChatWorkspace(
                    persistentStore: persistent,
                    registry: registry,
                    selection: selection
                )
                // Read once, then copied into each chat as it is created. Changing the default later
                // cannot rewrite a conversation the user already has.
                builtWorkspace.apply(defaults: builtTheme.settings.defaultChatConfig)
                let builtServers = ServersModel(
                    storing: persistent,
                    testing: factory.tester(),
                    managing: factory.modelService(),
                    secrets: secrets,
                    registry: registry,
                    baseEngines: [MockStreamingProvider()],
                    selection: selection,
                    discovering: LANDiscoveryService(),
                    engineBuilder: { profiles in factory.providers(from: profiles) }
                )
                // The Servers screen never reaches into the chat: it reports the chosen server, and
                // the workspace points the live session at it.
                builtServers.onActiveServerChange = { profile in
                    builtWorkspace.apply(activeProfile: profile)
                }
                workspace = builtWorkspace
                servers = builtServers
                theme = builtTheme
            } catch {
                // Typed metadata only: never log prompt content, URLs, or paths.
                startupFailure = error.localizedDescription
            }
        }
    }
}
