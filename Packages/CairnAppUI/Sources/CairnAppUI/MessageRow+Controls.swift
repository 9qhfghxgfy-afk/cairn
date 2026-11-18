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

    @ViewBuilder
    var metricsFooter: some View {
        if let metrics = node.metrics {
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
