import Foundation

/// Value-in / value-out tree mutations. History is never rewritten: every edit,
/// regeneration, and branch appends a sibling and leaves the old path intact.
public extension ChatTree {

    struct AppendResult: Sendable, Equatable {
        public var node: ChatNode
        public var nodes: [ChatNode]

        public init(node: ChatNode, nodes: [ChatNode]) {
            self.node = node
            self.nodes = nodes
        }
    }

    static func append(
        to nodes: [ChatNode],
        conversationID: UUID,
        parentID: UUID?,
        role: ChatRole,
        text: String = "",
        kind: NodeKind = .plain,
        state: NodeState = .complete,
        providerID: String? = nil,
        modelID: String? = nil,
        now: Date = Date(),
        attachments: [ChatAttachment] = [],
        citations: [SourceCitation] = []
    ) -> AppendResult {
        let node = ChatNode(
            conversationID: conversationID,
            parentID: parentID,
            role: role,
            kind: kind,
            text: text,
            state: state,
            branchIndex: nextBranchIndex(in: nodes, parentID: parentID),
            providerID: providerID,
            modelID: modelID,
            createdAt: now,
            attachments: attachments,
            citations: citations
        )
        return AppendResult(node: node, nodes: nodes + [node])
    }

    /// Edit = a new sibling of the edited node under the SAME parent carrying the
    /// new text. The original node and everything below it remain a branch.
    ///
    /// The sibling carries the original's attachments. An edit changes the words; it does not un-attach
    /// the photo or the document the user pinned to that message, and a sibling that quietly arrived
    /// without them would be a message missing a file the user can still see in the branch beside it.
    static func edit(
        nodes: [ChatNode],
        nodeID: UUID,
        newText: String,
        now: Date = Date()
    ) -> AppendResult? {
        guard let target = nodes.first(where: { $0.id == nodeID }) else { return nil }
        let replacement = ChatNode(
            conversationID: target.conversationID,
            parentID: target.parentID,
            role: target.role,
            kind: target.kind,
            text: newText,
            state: .complete,
            branchIndex: nextBranchIndex(in: nodes, parentID: target.parentID),
            providerID: target.providerID,
            modelID: target.modelID,
            createdAt: now,
            attachments: target.attachments
        )
        return AppendResult(node: replacement, nodes: nodes + [replacement])
    }

    /// Regenerate = a new assistant sibling attached to the same parent as the
    /// previous answer (the same user turn), starting empty and streaming.
    ///
    /// It carries the previous answer's citations: the question and the documents are the same ones, so
    /// the sources the passages came from are the same sources. Dropping them would make a regenerated
    /// answer look ungrounded when it was grounded in exactly the same passages.
    static func regenerate(
        nodes: [ChatNode],
        assistantNodeID: UUID,
        providerID: String?,
        modelID: String?,
        now: Date = Date()
    ) -> AppendResult? {
        guard let target = nodes.first(where: { $0.id == assistantNodeID }) else { return nil }
        let fresh = ChatNode(
            conversationID: target.conversationID,
            parentID: target.parentID,
            role: .assistant,
            kind: target.kind,
            text: "",
            state: .streaming,
            branchIndex: nextBranchIndex(in: nodes, parentID: target.parentID),
            providerID: providerID,
            modelID: modelID,
            createdAt: now,
            citations: target.citations
        )
        return AppendResult(node: fresh, nodes: nodes + [fresh])
    }

    /// A synthesized turn is ONE assistant node that carries its candidate drafts.
    static func synthesizedNode(
        nodes: [ChatNode],
        conversationID: UUID,
        parentID: UUID?,
        drafts: [CandidateDraft],
        providerID: String?,
        modelID: String?,
        now: Date = Date()
    ) -> AppendResult {
        hybridNode(
            nodes: nodes,
            conversationID: conversationID,
            parentID: parentID,
            kind: .synthesized,
            drafts: drafts,
            providerID: providerID,
            modelID: modelID,
            now: now
        )
    }

    /// Either hybrid shape is ONE assistant node carrying its candidate drafts, so a hybrid turn
    /// replays, exports, and branches exactly like any other single answer. The kind says whether
    /// the node's own text is a unified answer or the primary side of a comparison.
    static func hybridNode(
        nodes: [ChatNode],
        conversationID: UUID,
        parentID: UUID?,
        kind: NodeKind,
        drafts: [CandidateDraft] = [],
        providerID: String?,
        modelID: String?,
        now: Date = Date()
    ) -> AppendResult {
        let node = ChatNode(
            conversationID: conversationID,
            parentID: parentID,
            role: .assistant,
            kind: kind,
            text: "",
            state: .streaming,
            branchIndex: nextBranchIndex(in: nodes, parentID: parentID),
            providerID: providerID,
            modelID: modelID,
            createdAt: now,
            drafts: drafts.sorted { $0.order < $1.order }
        )
        return AppendResult(node: node, nodes: nodes + [node])
    }

    /// The node kind a mode produces, or nil when the mode is not a hybrid one. One place
    /// decides it, so a turn's kind and the mode that ran it cannot drift.
    static func hybridKind(for mode: InferenceMode) -> NodeKind? {
        switch mode {
        case .hybridParallel: return .hybridParallel
        case .hybridSynthesized: return .synthesized
        case .onDeviceOnly, .remoteOnly: return nil
        }
    }

    /// Moves to another sibling of `nodeID` — the `< 1 / N >` stepper.
    static func selectSibling(nodes: [ChatNode], nodeID: UUID, delta: Int) -> ChatNode? {
        guard let target = nodes.first(where: { $0.id == nodeID }) else { return nil }
        let sibs = siblings(of: target, in: nodes)
        guard let current = sibs.firstIndex(where: { $0.id == nodeID }) else { return nil }
        let next = min(max(current + delta, 0), sibs.count - 1)
        guard next != current else { return nil }
        return sibs[next]
    }
}
