import Foundation

/// The single-node write for a hybrid turn. One assistant node carries the text, the drafts,
/// the provenance and the attribution, and each of them is written here from the same outcome
/// or the same draft — so a partial answer survives a stop, and a node can never be credited
/// to an engine that did not write its text.
extension ChatSessionModel {


    /// Writes one side's partial answer into the one node as it lands, so a stop, a
    /// backgrounding, or a crash keeps what every engine already said.
    func writeDraft(_ draft: CandidateDraft, to nodeID: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        var node = nodes[index]
        if let existing = node.drafts.firstIndex(where: { $0.order == draft.order }) {
            var kept = draft
            // Keep the row's identity: an id that changes every chunk rebuilds every card
            // mid-stream, and a fold the user just opened pops back open.
            kept.id = node.drafts[existing].id
            node.drafts[existing] = kept
        } else {
            node.drafts.append(draft)
        }
        node.drafts.sort { $0.order < $1.order }
        nodes[index] = node
        save(node)
        refreshPathIfNeeded(nodeID)
    }

    func persistHybridBody(
        nodeID: UUID,
        text: String,
        thinking: String?,
        metrics: GenerationMetrics?,
        state: NodeState
    ) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        var node = nodes[index]
        node.text = text
        node.thinking = thinking
        node.metrics = metrics
        node.state = state
        nodes[index] = node
        save(node)
        refreshPathIfNeeded(nodeID)
    }

    /// The one write that decides what this node says. Drafts, provenance, attribution, and text
    /// all come from the same outcome, so they cannot disagree.
    func storeOutcome(_ result: HybridTurnOutcome, on nodeID: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        var node = nodes[index]
        let writer = primaryDraft(in: result.drafts)
        node.drafts = result.drafts
        node.provenance = result.provenance
        if !result.primaryText.isEmpty { node.text = result.primaryText }
        // Reasoning only from the synthesizer that wrote this node's text — never from a draft.
        node.thinking = result.synthesis?.thinking
        node.metrics = result.synthesis?.metrics ?? writer?.metrics
        if let engine = result.provenance.synthesizerEngineID ?? writer?.providerID {
            node.providerID = engine
            node.modelID = result.provenance.synthesizerModelID ?? writer?.modelID ?? node.modelID
        }
        node.state = result.state
        nodes[index] = node
        save(node)
        refreshPathIfNeeded(nodeID)
        mirrorPhase(result.state)
        if result.state == .failed { lastError = firstFailureReason(in: result) }
    }

    /// The side whose answer is standing as this node's text, which is also the side the node is
    /// attributed to when there is no synthesizer to attribute it to.
    func primaryDraft(in drafts: [CandidateDraft]) -> CandidateDraft? {
        drafts.first(where: { $0.answered })
            ?? drafts.first(where: { !$0.text.isEmpty })
            ?? drafts.first
    }

    func save(_ node: ChatNode) {
        do {
            try store.saveNode(node)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshPathIfNeeded(_ nodeID: UUID) {
        guard path.contains(where: { $0.id == nodeID }) else { return }
        path = ChatTree.visiblePath(nodes: nodes, activeLeafID: conversation.activeLeafID)
    }
}
