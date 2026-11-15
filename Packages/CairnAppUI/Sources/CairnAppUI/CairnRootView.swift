import SwiftUI
import CairnChatDomain

/// Entry view. Milestone 1 wires exactly one engine — the mock — so the whole app is
/// exercisable end to end before any socket exists.
public struct CairnRootView: View {
    private let workspace: ChatWorkspace
    /// Present once the app wires server-profile storage (M2); the toolbar gear then opens
    /// the Servers screen. M1 call sites keep working unchanged.
    private var servers: ServersModel?
    @State private var showingServers = false

    public init(workspace: ChatWorkspace, servers: ServersModel? = nil) {
        self.workspace = workspace
        self.servers = servers
    }

    public var body: some View {
        NavigationStack {
            ChatScreen(workspace: workspace)
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
                }
        }
        .sheet(isPresented: $showingServers) {
            if let servers {
                NavigationStack {
                    ServersView(model: servers)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await workspace.start() }
    }
}
