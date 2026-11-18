import SwiftUI
import CairnChatDomain

/// One candidate's draft inside a hybrid node, collapsed by default: who wrote it, what it said,
/// that side's own measured rate, and its typed reason when it failed.
///
/// The reasoning panel is gated on the draft's own `thinking` field. A side that emitted no reasoning
/// shows no panel — Cairn never writes a thinking display around an answer it has no reasoning for,
/// and never paraphrases another side's answer into one.
struct HybridDraftCard: View {
    let draft: CandidateDraft
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if hasOwnReasoning, let thinking = draft.thinking {
                    reasoning(thinking)
                }
                Text(draft.text.isEmpty ? "…" : draft.text)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                if let failure = draft.failure {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.rust)
                }
                metricsLine
            }
            .padding(.top, 4)
        } label: {
            label
        }
        .tint(colour)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(draft.sourceLabel.isEmpty ? draft.providerID : draft.sourceLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CairnTheme.amber)
            Text(draft.modelID)
                .font(.caption2.monospaced())
                .foregroundStyle(CairnTheme.stoneLight)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(stateText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colour)
        }
    }

    /// Measured from this side's own `.metrics` chunk, or absent. Never copied from another side and
    /// never estimated — these numbers are read next to the answer they describe.
    @ViewBuilder
    private var metricsLine: some View {
        if let metrics = draft.metrics {
            HStack(spacing: 10) {
                if let rate = metrics.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", rate))
                }
                Text("\(metrics.tokensGenerated) tok")
                Text(metrics.finishReason.rawValue)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(CairnTheme.stoneLight.opacity(0.8))
        }
    }

    private func reasoning(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("This side's reasoning", systemImage: "brain")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CairnTheme.moss)
            Text(thinking)
                .font(.callout.monospaced())
                .foregroundStyle(CairnTheme.stoneLight)
                .textSelection(.enabled)
        }
    }

    /// True only when this candidate's backend emitted reasoning. The field is the whole test — there
    /// is no fallback that invents a panel.
    var hasOwnReasoning: Bool {
        guard let thinking = draft.thinking else { return false }
        return !thinking.isEmpty
    }

    private var stateText: String {
        switch draft.state {
        case .streaming: return "writing"
        case .complete: return "done"
        case .failed: return "failed"
        case .cancelled: return "stopped"
        case .interrupted: return "paused"
        }
    }

    private var colour: Color {
        switch draft.state {
        case .failed: return CairnTheme.rust
        case .cancelled, .interrupted: return CairnTheme.amber
        case .streaming: return CairnTheme.amber
        case .complete: return CairnTheme.moss
        }
    }
}
