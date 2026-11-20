import SwiftUI
import CairnChatDomain

/// Selector menus for `ChatScreen`.
extension ChatScreen {

    /// The mode this chat answers in. Both hybrid modes are live now that the hybrid engine exists:
    /// a chat whose plan is not built yet is not hidden behind a disabled row, it is switched to and
    /// then told what is missing — in the header caption, in the configuration sheet, and again on the
    /// turn that refuses to start. One refusal, worded in one place.
    var modeMenu: some View {
        Menu {
            ForEach(InferenceMode.allCases) { mode in
                Button {
                    workspace.mode = mode
                } label: {
                    // The name alone is four guesses. The line under it says who runs the answer and
                    // whether a byte leaves the phone, which is the whole decision; the full note is
                    // one more tap on the `(i)` beside the pill.
                    VStack(alignment: .leading, spacing: 2) {
                        if workspace.mode == mode {
                            Label(modeTitle(mode), systemImage: "checkmark")
                        } else {
                            Text(modeTitle(mode))
                        }
                        Text(mode.shortNote)
                            .font(.caption)
                            .foregroundStyle(CairnTheme.stoneLight)
                    }
                }
            }
        } label: {
            pill(symbol: "square.2.layers.3d", title: modeTitle(workspace.mode))
        }
    }

    /// What the mode in force actually does, on tap, next to the mode's own name.
    var modeInfo: some View {
        InfoButton(title: workspace.mode.explainerTitle, text: workspace.mode.explainer)
            .accessibilityLabel("What \(workspace.mode.displayName) does")
    }

    /// The server and model switcher. A server row here is the same one tap as on the Servers
    /// screen: the session repoints, the shared choice records it, and the model that server was
    /// last used with comes back — a model name is never carried across to a machine that does not
    /// have it.
    var modelMenu: some View {
        Menu {
            Section("Server") {
                ForEach(workspace.providerIDs, id: \.self) { providerID in
                    Button {
                        chooseEngine(providerID)
                    } label: {
                        if session?.selectedProviderID == providerID {
                            Label(engineTitle(providerID), systemImage: "checkmark")
                        } else {
                            Text(engineTitle(providerID))
                        }
                    }
                }
            }
            Section("Model") {
                ForEach(session?.availableModels ?? []) { model in
                    Button {
                        session?.choose(model: model.id)
                    } label: {
                        if session?.selectedModelID == model.id {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
            }
        } label: {
            pill(symbol: "cpu", title: modelTitle)
        }
    }

    private func chooseEngine(_ providerID: String) {
        if let profileID = RemoteEngineID.parse(providerID) {
            session?.select(serverProfileID: profileID)
        } else {
            // The offline mock and any later on-device engine: no saved server behind it, so there
            // is no per-server model to restore.
            session?.select(providerID: providerID)
        }
    }

    /// Names the engine, and says out loud when its traffic leaves the network the user is on.
    private func engineTitle(_ providerID: String) -> String {
        let name = workspace.providerDisplayName(providerID)
        return workspace.providerNetworkClass(providerID) == .publicInternet
            ? "\(name) — public internet"
            : name
    }

    private var modelTitle: String {
        guard let session, !session.selectedModelID.isEmpty else { return "no model" }
        return session.selectedModelID
    }

    var temporaryToggle: some View {
        HStack(spacing: 4) {
            Button {
                workspace.temporaryChat.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: workspace.temporaryChat ? "flame.fill" : "tray.and.arrow.down")
                    Text(workspace.temporaryChat ? "Temporary" : "Saved")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill((workspace.temporaryChat ? CairnTheme.amber : CairnTheme.moss).opacity(0.22))
                )
                .foregroundStyle(workspace.temporaryChat ? CairnTheme.amber : CairnTheme.moss)
            }

            // The pill flips which store the conversation lives in, and it starts a new conversation when it
            // flips. That is worth one tap of reading before the tap that does it — said beside the pill,
            // because a note under a header the user is not looking at is a note nobody finds.
            InfoButton(key: .temporaryChat)
        }
    }

    func pill(symbol: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(CairnTheme.stone.opacity(0.6)))
        .foregroundStyle(CairnTheme.stoneLight)
    }

    func modeTitle(_ mode: InferenceMode) -> String { mode.displayName }
}
