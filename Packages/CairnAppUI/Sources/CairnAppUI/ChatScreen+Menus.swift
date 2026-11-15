import SwiftUI
import CairnChatDomain

/// Selector menus for `ChatScreen`.
extension ChatScreen {

    /// Hybrid modes are visible but disabled: the schema already stores a synthesized
    /// node from Milestone 1, and the engine that fills it lands in Milestone 4.
    var modeMenu: some View {
        Menu {
            ForEach(InferenceMode.allCases) { mode in
                Button {
                    workspace.mode = mode
                } label: {
                    if workspace.mode == mode {
                        Label(modeTitle(mode), systemImage: "checkmark")
                    } else {
                        Text(modeTitle(mode))
                    }
                }
                .disabled(mode != .onDeviceOnly && mode != .remoteOnly)
            }
        } label: {
            pill(symbol: "square.2.layers.3d", title: modeTitle(workspace.mode))
        }
    }

    var modelMenu: some View {
        Menu {
            Section("Engine") {
                ForEach(workspace.providerIDs, id: \.self) { providerID in
                    Button(providerID) { session?.select(providerID: providerID) }
                }
            }
            Section("Model") {
                ForEach(session?.availableModels ?? []) { model in
                    Button {
                        session?.selectedModelID = model.id
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
            pill(
                symbol: "cpu",
                title: session?.selectedModelID.isEmpty == false ? session!.selectedModelID : "no model"
            )
        }
    }

    var temporaryToggle: some View {
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

    func modeTitle(_ mode: InferenceMode) -> String {
        switch mode {
        case .onDeviceOnly: return "On device"
        case .remoteOnly: return "Remote"
        case .hybridParallel: return "Hybrid parallel (M4)"
        case .hybridSynthesized: return "Hybrid synthesized (M4)"
        }
    }
}
