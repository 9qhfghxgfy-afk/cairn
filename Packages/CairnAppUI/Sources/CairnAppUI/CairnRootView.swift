import SwiftUI
import CairnChatDomain

/// Entry view. Milestone 1 wires exactly one engine — the mock — so the whole app is
/// exercisable end to end before any socket exists.
public struct CairnRootView: View {
    private let workspace: ChatWorkspace

    public init(workspace: ChatWorkspace) {
        self.workspace = workspace
    }

    public var body: some View {
        NavigationStack {
            ChatScreen(workspace: workspace)
                .navigationTitle("Cairn")
                .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .task { await workspace.start() }
    }
}
