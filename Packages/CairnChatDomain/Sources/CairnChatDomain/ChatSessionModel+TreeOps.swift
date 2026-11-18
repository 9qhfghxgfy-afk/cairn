import Foundation

/// Tree entry points + streaming core for `ChatSessionModel`.
///
/// Members here are module-internal rather than `private` because Swift's
/// `private` is file-scoped and this type is split across two files on purpose:
/// one file for the tree entry points, one for the stream drain.
extension ChatSessionModel {

    /// Regenerate = a new assistant sibling under the same user turn. The previous
    /// answer is kept as another branch, so `< 1 / N >` can move between them.
    public func regenerate(assistantNodeID: UUID) {
        guard !isBusy else { return }
        guard let provider = activeProvider else {
            lastError = "No inference provider is selected."
            return
        }

        var working = nodes
        // A regenerated answer is asked over the same user message, so it carries that message's images
        // again. A photo whose file has gone stops the turn before anything is written, rather than leaving
        // an empty answer on the tree and a new one that never saw the picture. The path read is the one
        // the answer being replaced sits on — the new sibling does not exist yet, and the question beside it
        // is what decides which images are needed.
        guard attachmentsReadable(
            in: ChatTree.visiblePath(nodes: working, activeLeafID: assistantNodeID)
        ) else {
            lastError = Self.unreadableAttachmentMessage
            return
        }
        do {
            guard let result = ChatTree.regenerate(
                nodes: working,
                assistantNodeID: assistantNodeID,
                providerID: provider.id,
                modelID: selectedModelID,
                now: Date()
            ) else {
                lastError = StoreError.nodeNotFound(assistantNodeID).errorDescription
                return
            }
            working = result.nodes
            try store.saveNode(result.node)

            var updated = conversation
            updated.activeLeafID = result.node.id
            updated.updatedAt = Date()
            try store.saveConversation(updated)

            conversation = updated
            nodes = working
            path = ChatTree.visiblePath(nodes: working, activeLeafID: result.node.id)
            if conversation.mode.isHybrid {
                beginHybridTurn(assistantNodeID: result.node.id)
            } else {
                beginStreaming(assistantNodeID: result.node.id, provider: provider)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Edit = a sibling carrying the new text. Nothing below the old node is touched.
    public func edit(nodeID: UUID, newText: String) {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var working = nodes
        do {
            guard let result = ChatTree.edit(nodes: working, nodeID: nodeID, newText: text, now: Date()) else {
                lastError = StoreError.nodeNotFound(nodeID).errorDescription
                return
            }
            working = result.nodes
            try store.saveNode(result.node)

            var updated = conversation
            updated.activeLeafID = result.node.id
            updated.updatedAt = Date()
            try store.saveConversation(updated)

            conversation = updated
            nodes = working
            path = ChatTree.visiblePath(nodes: working, activeLeafID: result.node.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The `< 1 / N >` stepper on a node that has sibling branches.
    public func moveBranch(nodeID: UUID, delta: Int) {
        guard let target = ChatTree.selectSibling(nodes: nodes, nodeID: nodeID, delta: delta) else { return }
        do {
            var updated = conversation
            updated.activeLeafID = target.id
            updated.updatedAt = Date()
            try store.saveConversation(updated)
            conversation = updated
            path = ChatTree.visiblePath(nodes: nodes, activeLeafID: target.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func branchPosition(of node: ChatNode) -> ChatTree.BranchPosition {
        ChatTree.branchPosition(of: node, in: nodes)
    }

    public func cancelStreaming() {
        guard isBusy else { return }
        accumulator.requestCancellation()
        streamTask?.cancel()
    }
}
