import SwiftUI
import CairnChatDomain

/// Row controls for `MessageRow`: branch stepper, state tag, metrics, edit/regenerate.
/// Internal rather than private so they can live in their own file.
extension MessageRow {

    @ViewBuilder
    var stateBadge: some View {
        switch node.state {
        case .streaming:
            EmptyView()
        case .cancelled:
            tag("stopped", CairnTheme.amber)
        case .failed:
            tag("failed", CairnTheme.rust)
        case .interrupted:
            tag("paused", CairnTheme.amber)
        case .complete:
            // Both hybrid shapes are worth naming on a finished node: one answer was written from
            // several drafts, the other is two drafts held side by side.
            if node.kind == .synthesized { tag("synthesized", CairnTheme.moss) }
            if node.kind == .hybridParallel { tag("compared", CairnTheme.moss) }
        }
    }

    func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    /// `< 1 / N >` — the branch navigation the product spec calls for on every
    /// node that has siblings.
    @ViewBuilder
    var branchStepper: some View {
        let position = session.branchPosition(of: node)
        if position.total > 1 {
            HStack(spacing: 4) {
                Button {
                    session.moveBranch(nodeID: node.id, delta: -1)
                } label: { Image(systemName: "chevron.left") }
                .disabled(!position.canGoBack)

                Text("\(position.index)/\(position.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CairnTheme.stoneLight)

                Button {
                    session.moveBranch(nodeID: node.id, delta: 1)
                } label: { Image(systemName: "chevron.right") }
                .disabled(!position.canGoForward)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(CairnTheme.amber)
        }
    }

    /// The measurements this turn produced, drawn only when the `Generation Statistics` switch is up.
    ///
    /// The switch decides what is **drawn**, not what was recorded: `metrics` stays on the node either
    /// way, so turning the footer off does not un-measure a turn the user may want to inspect later.
    /// Elapsed seconds are shown because they are the number that explains a slow turn; tok/s is the
    /// one that explains a long one.
    @ViewBuilder
    var metricsFooter: some View {
        if session.showsGenerationStats, let metrics = node.metrics {
            HStack(spacing: 10) {
                Text(String(format: "%.1f s", metrics.elapsedSeconds))
                if let rate = metrics.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", rate))
                }
                Text("\(metrics.tokensGenerated) tok")
                Text(metrics.finishReason.rawValue)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(CairnTheme.stoneLight.opacity(0.8))
            .accessibilityLabel(generationStatsSpoken(metrics))
        }
    }

    private func generationStatsSpoken(_ metrics: GenerationMetrics) -> String {
        var parts: [String] = [String(format: "%.1f seconds", metrics.elapsedSeconds)]
        if let rate = metrics.tokensPerSecond {
            parts.append(String(format: "%.1f tokens per second", rate))
        }
        parts.append("\(metrics.tokensGenerated) tokens")
        parts.append("finished: \(metrics.finishReason.rawValue)")
        return "Generation statistics: \(parts.joined(separator: ", "))"
    }

    @ViewBuilder
    var controls: some View {
        if isEditing {
            HStack {
                TextField("Edit message", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    session.edit(nodeID: node.id, newText: draftText)
                    isEditing = false
                }
                Button("Cancel", role: .cancel) {
                    isEditing = false
                }
            }
        } else if node.role == .user {
            Button {
                draftText = node.text
                isEditing = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(CairnTheme.stoneLight)
        } else if node.role == .assistant, node.state != .streaming {
            Button {
                session.regenerate(assistantNodeID: node.id)
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(CairnTheme.stoneLight)
            .disabled(session.isBusy)
        }
    }
}
