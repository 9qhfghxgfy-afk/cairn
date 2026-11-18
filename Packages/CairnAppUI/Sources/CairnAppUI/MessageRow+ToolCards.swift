import SwiftUI
import CairnChatDomain

/// The tool half of a node: the calls this answer was built from, and what the turn was offered.
///
/// These live on the **one** assistant node, not on nodes of their own, for the same reason a hybrid
/// node's drafts do: a call is part of the answer it fed, so it replays, branches and exports with it.
/// A tool call that were its own tree node could be branched away from the answer it justified.
extension MessageRow {

    @ViewBuilder
    var toolRunCards: some View {
        if let run = node.toolRun, !run.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                // The loop's own shape in one line: calls, round trips, which protocol carried them,
                // and whether the step bound cut it short — stated by the run, never inferred here.
                Text(run.summaryText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CairnTheme.stoneLight)
                ForEach(run.invocations) { invocation in
                    ToolCallCard(invocation: invocation)
                }
                if run.usedWebTools {
                    ToolsOutboundBadge(
                        usedWebTools: true,
                        detail: "Reached the internet for this answer"
                    )
                }
            }
        } else if !node.toolsOffered.isEmpty {
            // Offered and not used is worth its own line: it is the difference between "the model chose
            // not to call" and "this chat has no tools", and only the transcript can tell them apart
            // once the settings have moved on.
            Text("Offered this turn: \(node.toolsOffered.joined(separator: ", ")) — none called")
                .font(.caption2)
                .foregroundStyle(CairnTheme.stoneLight.opacity(0.8))
        }
    }
}
