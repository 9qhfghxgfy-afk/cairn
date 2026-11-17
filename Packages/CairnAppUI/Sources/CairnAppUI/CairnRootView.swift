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
    @State private var showingServers = false
    @State private var showingSettings = false

    public init(
        workspace: ChatWorkspace,
        servers: ServersModel? = nil,
        settings: ThemeModel? = nil
    ) {
        self.workspace = workspace
        self.servers = servers
        self.settings = settings
    }

    public var body: some View {
        NavigationStack {
            ChatScreen(workspace: workspace, settings: settings)
                .navigationTitle("Cairn")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
        // The chosen palette, from the stored theme id: the accent actions take, the surface the app
        // sits on, and which half of the system appearance to pin. Nothing here changes where a prompt
        // goes — a theme is a look, never a network decision.
        .cairnChrome(
            settings?.palette ?? .trailhead,
            scheme: settings?.colorScheme
        )
        .task { await workspace.start() }
    }
}
