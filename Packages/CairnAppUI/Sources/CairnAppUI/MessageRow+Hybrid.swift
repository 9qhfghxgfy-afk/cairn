import SwiftUI
import CairnChatDomain

/// The hybrid half of a message row: the candidate drafts one node carries, and the one line that
/// says how this answer was produced.
///
/// Both are read straight off the node, so a card can never disagree with the text above it, and a
/// provenance line can never credit an engine that did not write this node.
extension MessageRow {

    /// The drafts a hybrid turn kept, each one collapsible. They are written as they land, so a turn
    /// still in flight shows its sides part-way answered, and a stopped turn shows exactly what each
    /// side had said when it was stopped.
    @ViewBuilder
    var hybridDrafts: some View {
        if node.kind.isHybrid, !node.drafts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Candidate drafts · \(node.drafts.count)",
                    systemImage: "square.2.layers.3d"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(CairnTheme.stoneLight)

                ForEach(node.drafts) { draft in
                    HybridDraftCard(draft: draft)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CairnTheme.slate.opacity(0.5))
            )
        }
    }

    /// One line, in the words `HybridProvenance` itself produces: which engines were asked, which one
    /// wrote the unified answer, and how many drafts failed. Counts and ids only — no prompt text, and
    /// nothing that leaves this device.
    @ViewBuilder
    var provenanceFooter: some View {
        if let provenance = node.provenance {
            Text(provenance.summary)
                .font(.caption2)
                .foregroundStyle(CairnTheme.stoneLight.opacity(0.8))
        }
    }

    /// Who the row says wrote it. A synthesized node is named for the writer, a parallel node for the
    /// comparison, and every other assistant node stays "Cairn".
    var roleTitle: String {
        guard node.role == .assistant else { return "You" }
        switch node.kind {
        case .synthesized: return "Synthesized"
        case .hybridParallel: return "Compared"
        case .plain: return "Cairn"
        }
    }
}
