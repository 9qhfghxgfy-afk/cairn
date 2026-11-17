import SwiftUI
import CairnChatDomain

/// The "How do I get started?" sheet, opened from the empty Servers screen.
///
/// It teaches the actual model of the app: Cairn runs nothing itself, so a server has to exist
/// somewhere, and the phone then talks to it over the network the user is already on. Everything
/// here is prose the domain rules back up — private addresses over http, https plus opt-in for
/// anything public, nothing leaving the device unless the user said so.
struct ServersGuide: View {
    var onAdd: (@MainActor (ServerProfileKind) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    guideStep(
                        number: 1,
                        title: "Run a server somewhere",
                        body: "Cairn does not run a model on this phone yet. Ollama on a Mac, Linux box, or Windows PC, or LM Studio on a desktop, both work. The phone only needs something to ask."
                    )
                    guideStep(
                        number: 2,
                        title: "Make sure it listens on your network",
                        body: "By default some servers answer only the machine they run on. Start Ollama with its host set to the network, or turn on LM Studio's server, so the phone can reach it."
                    )
                    guideStep(
                        number: 3,
                        title: "Add its address here",
                        body: "Use the server's address on your network with http — a LAN address, a router address, or a .local name. Nothing on the public internet is accepted over http; that needs https and your explicit permission."
                    )
                    guideStep(
                        number: 4,
                        title: "Allow Local Network access",
                        body: "The first attempt from this iPhone shows an iOS prompt. Allow it: if you deny it, every connection to your own network fails, and no scan can find anything."
                    )
                } header: {
                    Text("From nothing to a working server")
                } footer: {
                    Text("Your chats, settings, and attachments stay on this device. A prompt only leaves it when you add a server and send it something.")
                }

                Section("Two quick routes") {
                    Button {
                        onAdd?(.ollama)
                        dismiss()
                    } label: {
                        guideRoute(title: "Ollama", detail: "Native API, port 11434, model list and pull support")
                    }
                    Button {
                        onAdd?(.lmStudio)
                        dismiss()
                    } label: {
                        guideRoute(title: "LM Studio", detail: "Its own REST server, port 1234, with an OpenAI-compatible chat endpoint")
                    }
                    Button {
                        onAdd?(.openAICompatible)
                        dismiss()
                    } label: {
                        guideRoute(title: "Anything OpenAI-compatible", detail: "llama.cpp's server, vLLM, a container — usually port 8080 or 1234")
                    }
                }
            }
            .navigationTitle("How do I get started?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func guideStep(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(CairnTheme.amber)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func guideRoute(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout)
            Text(detail)
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
        }
        .contentShape(Rectangle())
    }
}
