import SwiftUI
import CairnChatDomain

/// The pinned On-Device row: what this phone can run by itself, and the Model Manager.
///
/// It is pinned above the server list because it is the one engine that needs no server, and it
/// reads a plain `OnDeviceEngineReport` handed over by the App layer. CairnAppUI imports neither
/// the Apple framework runtime nor the MLX module, so a view here can never call a provider — it
/// can only show what it was told.
struct OnDeviceEngineSection: View {
    private var model: ServersModel

    init(model: ServersModel) { self.model = model }

    var body: some View {
        Section {
            ForEach([report.appleModel, report.mlx], id: \.name) { state in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.name)
                        Text(state.status)
                            .font(.caption)
                            .foregroundStyle(CairnTheme.stoneLight)
                    }
                    Spacer()
                    // Words, not a coloured circle: "ready" and "not ready" have to be readable
                    // without colour vision, and the reason is already in the status line.
                    Text(state.isUsable ? "ready" : "not ready")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CairnTheme.stone.opacity(0.25), in: Capsule())
                        .foregroundStyle(state.isUsable ? CairnTheme.moss : CairnTheme.stoneLight)
                }
                .accessibilityElement(children: .combine)
            }

            if let manager = model.modelManager {
                NavigationLink {
                    ModelManagerView(model: manager)
                } label: {
                    Label("Model Manager", systemImage: "shippingbox")
                }
                .task {
                    let target = manager.profile ?? model.activeProfile()
                    if let target { await manager.open(target) }
                }
            }
        } header: {
            Text("On-Device")
        } footer: {
            Text(report.summary)
        }
    }

    private var report: OnDeviceEngineReport { model.onDeviceReport }
}
