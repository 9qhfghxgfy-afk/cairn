import SwiftUI
import CairnChatDomain

/// The Servers screen: one row per configured server, each stating where its traffic goes
/// before the user can send a single token there.
///
/// Built against `ServersModel`, whose collaborators are domain protocols, so this file
/// imports neither URLSession nor SwiftData.
public struct ServersView: View {
    private var model: ServersModel
    /// The profile open in the editor: a saved one, or a draft from Add / from a scan result. It
    /// is a `ServerProfile` rather than a flag so the editor always starts from what that kind of
    /// server should look like.
    @State private var editing: ServerProfile?
    @State private var showingGuide = false

    public init(model: ServersModel) {
        self.model = model
    }

    public var body: some View {
        List {
            // Pinned first: the one engine that needs no server, and the Model Manager that covers
            // every server's loaded and installed models.
            OnDeviceEngineSection(model: model)

            if let notice = model.notice {
                ServersNoticeBanner(text: notice)
            }

            if model.profiles.isEmpty {
                ServersEmptyState(
                    onAdd: { kind in editing = model.draft(for: kind) },
                    onGuide: { showingGuide = true },
                    onScan: { model.scanLocalNetwork() }
                )
            } else {
                ForEach(model.profiles) { profile in
                    ServerProfileRow(model: model, profile: profile)
                }
            }

            LANDiscoveryResults(model: model) { server in
                editing = model.draft(for: server)
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingGuide = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("How do I get started?")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // OpenAI-compatible first in the list after the two named apps: llama.cpp,
                    // LM Studio's server, and most containers speak that dialect.
                    Button("Ollama") { editing = model.draft(for: .ollama) }
                    Button("LM Studio") { editing = model.draft(for: .lmStudio) }
                    Button("OpenAI-compatible") { editing = model.draft(for: .openAICompatible) }
                    Button("Ollama Cloud") { editing = model.draft(for: .ollamaCloud) }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add server")
            }
        }
        .sheet(item: $editing) { profile in
            NavigationStack {
                ServerProfileEditor(model: model, profile: profile)
            }
        }
        .sheet(isPresented: $showingGuide) {
            ServersGuide(onAdd: { kind in editing = model.draft(for: kind) })
        }
    }
}

/// The first-run screen inside the Servers list. It says what Cairn is not — a model that runs on
/// the phone — and gives three ways out: pick a server kind, read the guide, or scan the network
/// the phone is already on.
struct ServersEmptyState: View {
    var onAdd: @MainActor (ServerProfileKind) -> Void
    var onGuide: @MainActor () -> Void
    var onScan: @MainActor () -> Void

    var body: some View {
        Section {
            ContentUnavailableView {
                Label("No servers yet", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text("A model can run on this phone if the row above says it is ready, with no server involved. Otherwise add a server you run — Ollama, LM Studio, or anything OpenAI-compatible — and this app talks to it over your own network.")
            }

            Button {
                onGuide()
            } label: {
                Label("How do I get started?", systemImage: "questionmark.circle")
            }
            .font(.callout.weight(.semibold))

            ForEach(ServerProfileKind.allCases) { kind in
                Button {
                    onAdd(kind)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add \(kind.displayName)")
                                .font(.callout)
                            Text(kindHint(kind))
                                .font(.caption)
                                .foregroundStyle(CairnTheme.stoneLight)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(CairnTheme.stoneLight)
                    }
                }
            }

            Button {
                onScan()
            } label: {
                Label("Scan my local network", systemImage: "dot.viewfinder")
            }
        } footer: {
            Text("A private address on your own network is reached over http. Anything on the public internet needs https and your explicit permission, and Cairn shows a badge on every server whose traffic leaves the device.")
        }
    }

    /// What the kind is, in the terms that decide whether it is the right one — its usual port and
    /// what it can do, straight from the declared backend so this cannot drift from the code.
    private func kindHint(_ kind: ServerProfileKind) -> String {
        let backend = kind.backend
        var parts: [String] = []
        if let port = backend.defaultPort { parts.append("port \(port)") }
        if kind == .ollamaCloud {
            parts.append("hosted by Ollama — needs a key, and starts switched off")
        } else if kind == .lmStudio {
            parts.append("its own model list, OpenAI-compatible chat")
        } else if kind == .ollama {
            parts.append("model list, pull, and loaded-model info")
        } else {
            parts.append("model list and chat only")
        }
        return parts.joined(separator: " · ")
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
