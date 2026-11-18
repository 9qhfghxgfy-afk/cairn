import SwiftUI
import CairnChatDomain

/// Entry view. Milestone 1 wires exactly one engine — the mock — so the whole app is
/// exercisable end to end before any socket exists.
public struct CairnRootView: View {
    private let workspace: ChatWorkspace
    /// Present once the app wires server-profile storage (M2); the toolbar gear then opens
    /// the Servers screen. M1 call sites keep working unchanged.
    private var servers: ServersModel?
    /// App-wide settings: the theme painted on this screen, and the Default Configuration new chats
    /// start from. Optional so previews and tests can build a root view with no store behind it.
    private var settings: ThemeModel?
    /// The thing that can resize a photo before it joins a message. Handed through rather than reached for:
    /// `CairnAppUI` may draw an image, but the size a photo becomes is the domain's rule
    /// (`ImagePreparationPolicy`), and the codec that applies it belongs to the app.
    private var imagePreparer: (any ImagePreparing)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingServers = false
    @State private var showingSettings = false
    @State private var showingChats = false

    public init(
        workspace: ChatWorkspace,
        servers: ServersModel? = nil,
        settings: ThemeModel? = nil,
        imagePreparer: (any ImagePreparing)? = nil
    ) {
        self.workspace = workspace
        self.servers = servers
        self.settings = settings
        self.imagePreparer = imagePreparer
    }

    public var body: some View {
        NavigationStack {
            ChatScreen(workspace: workspace, settings: settings, imagePreparer: imagePreparer)
                .navigationTitle("Cairn")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The list of chats leads, not trails: it is where a conversation comes from, and on a
                    // one-handed phone a leading thumb reaches it while a trailing one has to stretch.
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingChats = true
                        } label: {
                            Image(systemName: "folder")
                        }
                        .accessibilityLabel("Chats")
                    }
                    if servers != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingServers = true
                            } label: {
                                Image(systemName: "server.rack")
                            }
                            .accessibilityLabel("Servers")
                        }
                    }
                    if settings != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Settings")
                        }
                    }
                }
        }
        .sheet(isPresented: $showingChats) {
            // A stack of its own, because the list searches and pushes screens of its own; and it is the
            // workspace that acts, so opening a chat here re-reads the store rather than a row on screen.
            NavigationStack {
                ChatListView(workspace: workspace)
            }
        }
        .sheet(isPresented: $showingServers) {
            if let servers {
                NavigationStack {
                    ServersView(model: servers)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            if let settings {
                NavigationStack {
                    SettingsView(theme: settings, workspace: workspace)
                }
            }
        }
        // The chosen theme, from the stored theme id: the accent actions take, the surface the app
        // sits on, and which half of it to paint. Nothing here changes where a prompt goes — a theme
        // is a look, never a network decision.
        .cairnChrome(
            settings?.palette ?? .trailhead,
            appearance: settings?.settings.appearance ?? .system
        )
        .task { await workspace.start() }
        .onChange(of: scenePhase) { _, phase in
            // Going to the background really does end a turn. iOS suspends the app and takes the socket
            // with it, so an answer that appears to "keep streaming" is a stream frozen mid-sentence. It is
            // stopped here and marked paused rather than complete, which is what makes Continue on that row
            // a real offer instead of a button that redoes the whole turn.
            if phase == .background { workspace.session?.interruptActiveTurn() }
        }
    }
}
