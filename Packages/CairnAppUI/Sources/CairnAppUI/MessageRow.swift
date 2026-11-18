import SwiftUI
import CairnChatDomain

/// One node on the active path. Reasoning is rendered ONLY when the node actually
/// carries thinking text, which only happens if the backend emitted it.
public struct MessageRow: View {
    let session: ChatSessionModel
    let node: ChatNode
    /// The active theme's colours, so the transcript is the theme the user picked rather than the one
    /// the app shipped with. Status colours stay fixed on purpose — see `CairnTheme`.
    @Environment(\.cairnTokens) private var tokens

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
                .foregroundStyle(tokens.onCanvas)
                .textSelection(.enabled)

            // One hybrid node holds several drafts; they hang off the answer they were folded into,
            // so the card for a side can never drift from the text above it.
            hybridDrafts

            // The calls this answer was built from, beside the answer — including the ones still
            // running, which is how a multi-step turn reads as work in progress rather than a hang.
            toolRunCards

            if node.role == .assistant { metricsFooter }
            provenanceFooter
            controls
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(node.role == .user ? tokens.userBubble : tokens.assistantBubble)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(borderColor.opacity(0.5), lineWidth: 1)
                )
        )
    }

    var header: some View {
        HStack(spacing: 8) {
            Text(roleTitle)
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

    /// The node's own reasoning, collapsed by default, present only when the node actually carries
    /// thinking text — which happens only when a backend emitted it. A candidate's own reasoning hangs
    /// off its own draft card, gated the same way. Nothing here is ever paraphrased into existence.
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
