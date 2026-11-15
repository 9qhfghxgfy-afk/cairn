import SwiftUI
import CairnChatDomain

/// One node on the active path. Reasoning is rendered ONLY when the node actually
/// carries thinking text, which only happens if the backend emitted it.
public struct MessageRow: View {
    let session: ChatSessionModel
    let node: ChatNode

    @State var isEditing = false
    @State var draftText = ""

    public init(session: ChatSessionModel, node: ChatNode) {
        self.session = session
        self.node = node
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let thinking = node.thinking, !thinking.isEmpty {
                reasoningPanel(thinking)
            }
            Text(node.text.isEmpty ? "…" : node.text)
                .foregroundStyle(node.role == .user ? CairnTheme.stoneLight : .white)
                .textSelection(.enabled)

            if node.role == .assistant { metricsFooter }
            controls
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(node.role == .user ? CairnTheme.stone.opacity(0.55) : CairnTheme.slate)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(borderColor.opacity(0.5), lineWidth: 1)
                )
        )
    }

    var header: some View {
        HStack(spacing: 8) {
            Text(node.role == .user ? "You" : (node.kind == .synthesized ? "Synthesized" : "Cairn"))
                .font(.caption.weight(.bold))
                .foregroundStyle(CairnTheme.amber)

            if let model = node.modelID, !model.isEmpty {
                Text(model)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CairnTheme.stoneLight)
            }

            stateBadge

            Spacer(minLength: 0)

            branchStepper
        }
    }

    /// Collapsed by default. Per-draft panels and timers land with the Hybrid
    /// engine; the gate (real reasoning only) is already enforced here.
    func reasoningPanel(_ thinking: String) -> some View {
        DisclosureGroup {
            Text(thinking)
                .font(.callout.monospaced())
                .foregroundStyle(CairnTheme.stoneLight)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            Label("Model reasoning", systemImage: "brain")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CairnTheme.moss)
        }
        .tint(CairnTheme.moss)
    }

    var borderColor: Color {
        switch node.state {
        case .failed: return CairnTheme.rust
        case .cancelled, .interrupted: return CairnTheme.amber
        case .streaming: return CairnTheme.amber.opacity(0.7)
        case .complete: return CairnTheme.stone
        }
    }
}
