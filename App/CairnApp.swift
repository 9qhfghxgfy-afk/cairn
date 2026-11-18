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
    /// The tool assembly, kept alive for the life of the app: it holds the mail composer and reads
    /// Settings and the Keychain on behalf of the tools every chat gets.
    @State private var toolWiring: ToolWiring?
    /// A chat file that arrived before the workspace existed. iOS hands an opened file over in the same
    /// moment it launches the app, so the file is held for a beat and imported as soon as there is a store
    /// to import it into — rather than dropped on the floor because the launch lost a race.
    @State private var pendingImportURL: URL?

    var body: some View {
        Group {
            if let workspace {
                // `ImageIOPreparer` is the app's way of resizing a photo: the domain decided the size
                // (`ImagePreparationPolicy`) and cannot decode a pixel, so the seam is handed in here. A root
                // view built without one — a preview, a test — gets the honest passthrough instead.
                CairnRootView(
                    workspace: workspace,
                    servers: servers,
                    settings: theme,
                    imagePreparer: ImageIOPreparer()
                )
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
        .onOpenURL { url in
            // A chat file another app handed over: Mail, Files, a share sheet. Nothing is fetched — the URL
            // is a file the system placed for this app, never an address, and an import only ever adds:
            // `ChatImport` gives a file whose ids are already here a fresh set, so opening a file cannot
            // overwrite a chat that already exists.
            if let workspace {
                importChatFile(url, into: workspace)
            } else {
                pendingImportURL = url
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
                // The file side of attachments, installed before any session exists, for the same reason the
                // memory answer is: a chat opened from the list must already be able to read back the photo its
                // own row names. Only this layer can hold the store and hand its reader down — the domain never
                // opens a file, and `CairnAppUI` may not import SwiftData.
                AttachmentWiring.install(on: builtWorkspace, store: persistent)
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

                // The tools a chat may reach. Built here because only this layer can hold a window (the
                // mail composer), app-wide Settings, and the Keychain at once — and the domain must not
                // reach for any of them. The calculator and the mail draft are always offered; the three
                // web tools join only once the outbound acknowledgement is up, which is a Settings value
                // and not something a chat can grant itself.
                let wiring = ToolWiring(settings: builtTheme, secrets: secrets, servers: builtServers)
                wiring.install(on: builtWorkspace)
                toolWiring = wiring

                workspace = builtWorkspace
                servers = builtServers
                theme = builtTheme

                // The file the app was launched with, if one arrived before there was anywhere to put it.
                if let pending = pendingImportURL {
                    pendingImportURL = nil
                    importChatFile(pending, into: builtWorkspace)
                }
            } catch {
                // Typed metadata only: never log prompt content, URLs, or paths.
                startupFailure = error.localizedDescription
            }
        }
        .onChange(of: theme?.settings.outboundWebAllowed ?? false) { _, _ in
            // Re-assemble the registry when the acknowledgement moves. Without this, arming a chat
            // straight after saying "yes, web tools may go out" would offer the calculator only, and the
            // web tools would look broken until the app were relaunched.
            if let workspace, let toolWiring { toolWiring.install(on: workspace) }
        }
        .onChange(of: theme?.settings.showsGenerationStats ?? true) { _, _ in
            // The statistics switch decides what is drawn, so it travels to the sessions the same way.
            if let workspace, let toolWiring { toolWiring.install(on: workspace) }
        }
    }

    /// Reading a chat file the system handed this app and putting it in the saved store.
    ///
    /// The claim is taken for the read and dropped straight after — a file outside the app belongs to the
    /// system, and holding a grant Cairn no longer needs would be keeping a permission nobody asked for.
    /// A file that is not a Cairn chat is refused by the importer, which writes the reason where the chat
    /// screen shows it; nothing is half-imported and nothing is logged.
    private func importChatFile(_ url: URL, into workspace: ChatWorkspace) {
        let claimed = url.startAccessingSecurityScopedResource()
        defer { if claimed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            workspace.lastError = "That file could not be read."
            return
        }
        workspace.importChatFile(data)
    }
}
