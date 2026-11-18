import SwiftUI
import CairnChatDomain

/// The live shape of a hybrid turn: one row per candidate, in plan order, showing its phase, how
/// many characters have landed, and its own measured rate.
///
/// Counts and rates only — never text. A panel that republishes on every chunk has to be cheap, and
/// a progress list must never become a place a conversation gets copied into. Order is the plan's
/// order, so the rows do not reshuffle as the sides answer at different speeds.
public struct HybridProgressView: View {
    private let snapshot: HybridSnapshot

    public init(snapshot: HybridSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.2.layers.3d")
                Text(snapshot.summary)
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(CairnTheme.amber)

            ForEach(snapshot.progress) { entry in
                row(entry)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CairnTheme.slate.opacity(0.7))
        )
    }

    private func row(_ entry: CandidateProgress) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: symbol(for: entry.phase))
                    .foregroundStyle(colour(for: entry.phase))
                Text(entry.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.modelID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CairnTheme.stoneLight)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.summary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(colour(for: entry.phase))
                if let rate = entry.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", rate))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(CairnTheme.moss)
                }
            }
            // A side's own failure, in its own row — one side failing is not the turn failing, and
            // the surviving side's answer still stands next to it.
            if let failure = entry.failure {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(CairnTheme.rust)
            }
        }
    }

    private func symbol(for phase: CandidatePhase) -> String {
        switch phase {
        case .queued: return "hourglass"
        case .streaming: return "waveform"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    private func colour(for phase: CandidatePhase) -> Color {
        switch phase {
        case .queued: return CairnTheme.stoneLight
        case .streaming: return CairnTheme.amber
        case .completed: return CairnTheme.moss
        case .failed: return CairnTheme.rust
        case .cancelled: return CairnTheme.amber
        }
    }
}
