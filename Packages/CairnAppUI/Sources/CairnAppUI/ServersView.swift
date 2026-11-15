import SwiftUI
import CairnChatDomain

/// The Servers screen: one row per configured server, each stating where its traffic goes
/// before the user can send a single token there.
///
/// Built against `ServersModel`, whose collaborators are domain protocols, so this file
/// imports neither URLSession nor SwiftData.
public struct ServersView: View {
    private var model: ServersModel
    @State private var newProfile: ServerProfile?

    public init(model: ServersModel) {
        self.model = model
    }

    public var body: some View {
        List {
            if let notice = model.notice {
                ServersNoticeBanner(text: notice)
            }
            ForEach(model.profiles) { profile in
                ServerProfileRow(model: model, profile: profile)
            }
        }
        .overlay {
            if model.profiles.isEmpty {
                ContentUnavailableView {
                    Label("No servers yet", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Add a server you run — Ollama, or anything OpenAI-compatible such as llama.cpp or LM Studio. A private LAN or VPN address may use http; anything on the public internet needs https.")
                }
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // OpenAI-compatible first: llama.cpp, LM Studio and most self-hosted
                    // servers speak that dialect, while Ollama's native API is a different one.
                    newProfile = ServerProfile(name: "", kind: .openAICompatible, baseURLString: "http://")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add server")
            }
        }
        .sheet(item: $newProfile) { profile in
            NavigationStack {
                ServerProfileEditor(model: model, profile: profile)
            }
        }
    }
}

/// Inline text for validation and connection failures. Plain prose only: never a hostname,
/// never a token, never response content.
struct ServersNoticeBanner: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(CairnTheme.rust)
            .accessibilityLabel("Problem: \(text)")
    }
}
