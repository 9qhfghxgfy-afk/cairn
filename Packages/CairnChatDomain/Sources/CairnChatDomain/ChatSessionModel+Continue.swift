import Foundation

/// Continue Generation and the backgrounding interrupt, both of which are about a turn that stopped
/// before it was finished.
///
/// The tree rule holds here exactly as it does for Edit and Regenerate: nothing already written is
/// rewritten. A continuation appends a sibling under the same parent, carrying the stopped answer as its
/// first text, and streams the rest into it — so `< 1 / N >` still shows the short answer beside the long
/// one, and the user can go back.
extension ChatSessionModel {

    /// True when this node can be picked up again. The row draws Continue on this answer alone.
    public func canContinue(_ node: ChatNode) -> Bool { ChatContinuation.canContinue(node) }

    /// Streams the rest of a stopped answer into a sibling that carries what already landed.
    public func continueGeneration(nodeID: UUID) {
        guard !isBusy else { return }
        guard let provider = activeProvider else {
            lastError = "No inference provider is selected."
            return
        }
        guard let stopped = nodes.first(where: { $0.id == nodeID }) else {
            lastError = StoreError.nodeNotFound(nodeID).errorDescription
            return
        }
        guard ChatContinuation.canContinue(stopped) else {
            lastError = ChatContinuation.nothingToContinue
            return
        }

        var working = nodes
        do {
            // Picking a stopped answer back up asks the same question again, so the same images go with
            // it. If a photo's file can no longer be read, the continuation stops here with a reason
            // rather than streaming an answer built without it.
            guard attachmentsReadable(
                in: ChatTree.visiblePath(nodes: working, activeLeafID: stopped.id)
            ) else {
                lastError = Self.unreadableAttachmentMessage
                return
            }
            // The sibling is seeded with the stopped text, so a stop half-way through the continuation
            // still leaves a whole answer rather than a second half of one.
            let result = ChatTree.append(
                to: working,
                conversationID: conversation.id,
                parentID: stopped.parentID,
                role: .assistant,
                text: stopped.text,
                kind: .plain,
                state: .streaming,
                providerID: provider.id,
                modelID: selectedModelID,
                now: Date(),
                // The continuation is the same answer to the same question over the same documents, so it
                // keeps the sources the stopped answer was credited with.
                citations: stopped.citations
            )
            working = result.nodes
            try store.saveNode(result.node)

            var updated = conversation
            updated.activeLeafID = result.node.id
            updated.updatedAt = Date()
            try store.saveConversation(updated)

            conversation = updated
            nodes = working
            path = ChatTree.visiblePath(nodes: working, activeLeafID: result.node.id)
            beginStreaming(
                assistantNodeID: result.node.id,
                provider: provider,
                history: ChatContinuation.requestHistory(working, stopped: stopped),
                carrying: stopped.text
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The app went to the background with a turn in flight.
    ///
    /// The partial text is already on the node — every chunk is written as it lands — so this only has to
    /// stop the stream and say *why* it stopped. `.interrupted` rather than `.cancelled` is the whole
    /// point: the user never pressed Stop, and the row offers Continue on this one.
    public func interruptActiveTurn() {
        guard isBusy else { return }
        interruptRequested = true
        accumulator.requestCancellation()
        streamTask?.cancel()
    }

    /// What a stopped single-provider stream writes as its final state: the user's Stop is `.cancelled`,
    /// a backgrounding is `.interrupted`, and both keep the same text.
    var stoppedState: NodeState { interruptRequested ? .interrupted : .cancelled }
}
