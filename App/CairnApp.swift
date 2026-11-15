import SwiftUI
import CairnAppUI
import CairnChatDomain
import CairnPersistence

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
    @State private var startupFailure: String?

    var body: some View {
        Group {
            if let workspace {
                CairnRootView(workspace: workspace)
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
                workspace = ChatWorkspace(
                    persistentStore: persistent,
                    ephemeralStore: EphemeralStore(),
                    providers: [MockStreamingProvider()]
                )
            } catch {
                // Typed metadata only: never log prompt content or paths.
                startupFailure = error.localizedDescription
            }
        }
    }
}
