import SwiftUI
import CairnAppUI
import CairnChatDomain
import CairnPersistence
import CairnProviderRemote
import CairnInferenceLocal

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
    /// The memory-pressure watch, kept alive for the life of the app process.
    @State private var onDeviceWatch: Task<Void, Never>?

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
                // The two on-device engines join the mock: the Apple model and MLX. Both are
                // `.onDevice`, so a turn that runs here sends nothing anywhere and shows no badge.
                let onDeviceEngines = OnDeviceWiring.engines()
                let registry = ProviderRegistry(providers: [MockStreamingProvider()] + onDeviceEngines)
                // One owner for "what is resident in this process": the memory-pressure watch releases
                // through this registry and a hybrid turn's residency answer reads and releases through
                // the same one, so the two paths cannot disagree about what is loaded.
                let onDeviceRegistry = OnDeviceModelRegistry()
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
                // The hybrid memory answer is injected before any session exists, so the first chat
                // the app opens already asks the real device question. Without this every session keeps
                // the domain default: one on-device model at a time, released between runs.
                builtWorkspace.residency = HybridWiring.residencyGate(onDeviceRegistry)
                // Read once, then copied into each chat as it is created. Changing the default later
                // cannot rewrite a conversation the user already has.
                builtWorkspace.apply(defaults: builtTheme.settings.defaultChatConfig)
                let builtServers = ServersModel(
                    storing: persistent,
                    testing: factory.tester(),
                    managing: factory.modelService(),
                    secrets: secrets,
                    registry: registry,
                    baseEngines: [MockStreamingProvider()] + onDeviceEngines,
                    selection: selection,
                    discovering: LANDiscoveryService(),
                    engineBuilder: { profiles in factory.providers(from: profiles) }
                )
                // The Servers screen never reaches into the chat: it reports the chosen server, and
                // the workspace points the live session at it.
                builtServers.onActiveServerChange = { profile in
                    builtWorkspace.apply(activeProfile: profile)
                }
                // What this phone can run by itself, read from the build and the hardware rather
                // than assumed, plus the Model Manager for every server's loaded and installed
                // models. Both are handed to the Servers screen as values and a view model, so
                // CairnAppUI never imports a runtime.
                builtServers.onDeviceReport = OnDeviceWiring.report()
                builtServers.modelManager = ModelManagerModel(
                    managing: factory.modelService(),
                    lifecycle: RemoteModelLifecycleService(
                        transport: URLSessionTransport(),
                        secrets: secrets
                    )
                )
                // A memory warning releases the resident on-device model. Held in state so the
                // watch is not deallocated the moment this closure returns.
                onDeviceWatch = OnDeviceWiring.startMemoryWatch(onDeviceRegistry)

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
