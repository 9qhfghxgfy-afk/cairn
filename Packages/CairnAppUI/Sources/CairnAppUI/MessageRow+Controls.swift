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
            HStack(spacing: 14) {
                Button {
                    draftText = node.text
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(CairnTheme.stoneLight)

                CopyButton("Copy") { node.text }
            }
        } else if node.role == .assistant, node.state != .streaming {
            HStack(spacing: 14) {
                Button {
                    session.regenerate(assistantNodeID: node.id)
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(CairnTheme.stoneLight)
                .disabled(session.isBusy)

                // Drawn only on an answer that really stopped short. The rule is the domain's — a stopped
                // or interrupted turn, or a finished one the server cut off at its token ceiling — and a
                // failed turn is left to Regenerate, because its error is the story there.
                if session.canContinue(node) {
                    Button {
                        session.continueGeneration(nodeID: node.id)
                    } label: {
                        Label("Continue", systemImage: "arrow.down.forward.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(CairnTheme.amber)
                    .disabled(session.isBusy)
                    .accessibilityHint("Adds the rest of this answer as a new branch, keeping this one")
                }

                copyMenu
            }
        }
    }

    /// Copy an answer as prose, or as the Markdown it was written in — two different texts, and the user
    /// needs to be able to choose. Prose is what a note or another chat wants; the source is what a file
    /// or a README wants. Neither is this screen's rendering: a code block copies its own exact lines from
    /// inside the block, where a highlighted span is not a string and a wrapped line is not a newline.
    private var copyMenu: some View {
        Menu {
            Button("Copy text") { Pasteboard.copy(answerProse) }
            Button("Copy Markdown") { Pasteboard.copy(node.text) }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(CairnTheme.stoneLight)
    }

    /// The answer with its markup resolved, which is what a reader of the screen actually saw. Markup is
    /// not content: a copy that carries `**` around a word is carrying the model's punctuation, not the
    /// emphasis. Text the parser could not read is handed back untouched rather than emptied.
    private var answerProse: String {
        let blocks = MarkdownParser.blocks(from: node.text)
        return blocks.isEmpty ? node.text : blocks.plainText
    }
}

