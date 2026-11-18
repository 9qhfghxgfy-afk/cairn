import SwiftUI
import CairnChatDomain

/// One executed tool call, as the transcript shows it.
///
/// One line by default — name, state, duration — because the user came for the answer and the calls are
/// its receipts. Open it and the card gives the arguments as the model wrote them, the exact text the
/// tool handed back, and the typed failure if there was one. Nothing here is paraphrased: the output is
/// the same text the model was given, which is the only way anyone can check that an answer matches the
/// evidence it was built from.
public struct ToolCallCard: View {
    let invocation: ToolInvocation

    public init(invocation: ToolInvocation) {
        self.invocation = invocation
    }

    public var body: some View {
        DisclosureGroup {
            details
        } label: {
            header
        }
        .tint(colour)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CairnTheme.slate.opacity(0.55))
        )
    }

    var header: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption)
            Text(invocation.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            // The outbound mark on the call itself: a search result arrived from somewhere, and which
            // call carried it is the question a user asks afterwards.
            if invocation.isWebTool {
                Image(systemName: "globe")
                    .font(.caption2)
                    .foregroundStyle(CairnTheme.rust)
                    .accessibilityLabel("Reached the internet")
            }
            Spacer(minLength: 0)
            if let duration = invocation.durationText {
                Text(duration)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            Text(stateText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colour)
        }
        .foregroundStyle(CairnTheme.moss)
    }

    @ViewBuilder
    var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !invocation.argumentsText.isEmpty { section("Called with", invocation.argumentsText) }
            if !invocation.output.isEmpty { section("Returned", invocation.output) }
            if let detail = invocation.detail, !detail.isEmpty { section("Said", detail) }
            if invocation.error == nil && invocation.output.isEmpty {
                Text("The tool returned no content.")
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            if invocation.truncated {
                Text("Result shortened to fit this chat's context budget.")
                    .font(.caption)
                    .foregroundStyle(CairnTheme.amber)
            }
        }
        .padding(.top, 4)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CairnTheme.stoneLight)
            Text(text)
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
                .textSelection(.enabled)
        }
    }

    private var symbol: String {
        switch invocation.state {
        case .running: return "gearshape.2"
        case .complete: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "pause.circle"
        }
    }

    private var stateText: String {
        switch invocation.state {
        case .running: return "running"
        case .complete: return "done"
        case .failed: return "failed"
        case .cancelled: return "stopped"
        }
    }

    private var colour: Color {
        switch invocation.state {
        case .running: return CairnTheme.amber
        case .complete: return CairnTheme.moss
        case .failed: return CairnTheme.rust
        case .cancelled: return CairnTheme.amber
        }
    }
}
