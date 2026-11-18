import Foundation

/// Writes a chat as readable Markdown.
///
/// This is the human copy; the `.cairn` file is the lossless one. A Markdown transcript still carries
/// every alternative answer rather than only the visible path, because the other answers are the user's
/// too — a file that dropped them would quietly rewrite history on the way out. Reasoning appears only
/// when a backend actually sent it, and then exactly as it was sent, never paraphrased.
public enum ChatTranscript {

    /// One chat, readable top to bottom: the path the user is looking at, then any branch not on it.
    public static func markdown(
        conversation: Conversation,
        nodes: [ChatNode],
        exportedAt: Date = Date()
    ) -> String {
        let own = nodes.filter { $0.conversationID == conversation.id }
        let path = ChatTree.visiblePath(nodes: own, activeLeafID: conversation.activeLeafID)
        // A chat with no leaf pointer still has messages worth reading, so the fallback is chronological
        // rather than nothing: a transcript may be incomplete, but it is never empty on a technicality.
        let shown = path.isEmpty ? own.sorted(by: earlier) : path

        var lines: [String] = ["# \(conversation.title)", ""]
        lines.append(
            "_\(own.count) message\(own.count == 1 ? "" : "s") · exported \(exportedAt.iso8601) · "
                + "Cairn `\(ChatExportBundle.formatMarker)` v\(ChatExportBundle.currentVersion)._"
        )
        lines.append("")
        for node in shown {
            lines.append(contentsOf: turn(node, in: own))
        }

        let shownIDs = Set(shown.map(\.id))
        let others = own.filter { !shownIDs.contains($0.id) }.sorted(by: earlier)
        if !others.isEmpty {
            lines.append("## Answers on other branches")
            lines.append("")
            lines.append("_Kept in the tree; the open path does not pass through these._")
            lines.append("")
            for node in others {
                lines.append(contentsOf: turn(node, in: own, label: "Branch"))
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    /// Every chat in one document, separated by rules.
    public static func markdown(
        conversations: [Conversation],
        nodes: [ChatNode],
        exportedAt: Date = Date()
    ) -> String {
        conversations
            .map { markdown(conversation: $0, nodes: nodes, exportedAt: exportedAt) }
            .joined(separator: "\n---\n\n")
    }

    static func earlier(_ lhs: ChatNode, _ rhs: ChatNode) -> Bool { lhs.createdAt < rhs.createdAt }

    static func turn(_ node: ChatNode, in nodes: [ChatNode], label: String = "") -> [String] {
        var lines: [String] = []
        let who = label.isEmpty ? node.role.rawValue : "\(label) — \(node.role.rawValue)"
        let details = annotations(for: node, in: nodes)
        lines.append(details.isEmpty ? "## \(who)" : "## \(who) — \(details.joined(separator: " · "))")
        lines.append("")
        lines.append(node.text.isEmpty ? "_(no text)_" : node.text)
        lines.append("")

        if let thinking = node.thinking, !thinking.isEmpty {
            lines.append("**Reasoning, as the model sent it**")
            lines.append("")
            for thought in thinking.components(separatedBy: "\n") {
                lines.append("> \(thought)")
            }
            lines.append("")
        }

        if node.kind.isHybrid, !node.drafts.isEmpty {
            lines.append("**Drafts behind this answer**")
            lines.append("")
            for draft in node.drafts.sorted(by: { $0.order < $1.order }) {
                lines.append("\(draft.order + 1). \(draftLine(draft))")
            }
            if let provenance = node.provenance {
                lines.append("")
                lines.append("_\(provenance.summary)_")
            }
            lines.append("")
        }

        if !node.toolsOffered.isEmpty {
            lines.append("**Tools this turn could reach:** \(node.toolsOffered.joined(separator: ", "))")
            lines.append("")
        }
        return lines
    }

    static func draftLine(_ draft: CandidateDraft) -> String {
        var parts: [String] = [draft.sourceLabel]
        if !draft.modelID.isEmpty { parts.append(draft.modelID) }
        if let perSecond = draft.metrics?.tokensPerSecond {
            parts.append(String(format: "%.1f tok/s", perSecond))
        }
        parts.append("\(draft.text.count) characters")
        if draft.state == .failed { parts.append("failed") }
        return parts.joined(separator: " · ")
    }

    static func annotations(for node: ChatNode, in nodes: [ChatNode]) -> [String] {
        var parts: [String] = [node.createdAt.iso8601]
        if let model = node.modelID, !model.isEmpty { parts.append(model) }
        let position = ChatTree.branchPosition(of: node, in: nodes)
        if position.total > 1 { parts.append("branch \(position.index) of \(position.total)") }
        switch node.state {
        case .complete: break
        case .streaming: parts.append("still generating when exported")
        case .cancelled: parts.append("stopped by the user")
        case .failed: parts.append("did not finish")
        case .interrupted: parts.append("interrupted by backgrounding")
        }
        return parts
    }
}
