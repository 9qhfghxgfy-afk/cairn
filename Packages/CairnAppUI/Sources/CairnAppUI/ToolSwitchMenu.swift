import SwiftUI
import CairnChatDomain

/// The per-tool switches behind the `Tools` chip.
///
/// A chip that means "all six" with no way to say "not the one that searches" is a single decision
/// wearing three tools. Here each tool is its own switch, and a web switch that the outbound
/// acknowledgement has not released stays disabled and says why — the state the user reaches by
/// choosing "only tools on this device" in the disclosure, which is a real state rather than a refusal.
struct ToolSwitchMenu: View {
    let session: ChatSessionModel
    let outboundAllowed: Bool
    @Environment(\.cairnTokens) private var tokens

    var body: some View {
        Menu {
            ForEach(BuiltInTool.allNames, id: \.self) { name in
                Toggle(
                    isOn: Binding(
                        get: { session.conversation.config.toolToggle.isOn(name) },
                        set: { session.setTool(name, on: $0) }
                    )
                ) {
                    Label(ToolSwitchLabels.title(name), systemImage: ToolSwitchLabels.symbol(name))
                }
                .disabled(!outboundAllowed && BuiltInTool.isWebTool(name))
            }
        } label: {
            Image(systemName: "slider.horizontal.below.rectangle")
                .font(.caption)
                .padding(6)
                .background(Capsule().fill(tokens.onCanvasMuted.opacity(0.16)))
                .foregroundStyle(tokens.accent)
        }
        .accessibilityLabel("Tool switches")
    }
    /// The words and the marks are `ToolSwitchLabels`, where a test can check that a name
    /// really is a symbol. An unknown name draws nothing, which is how a row once came up blank.
}
