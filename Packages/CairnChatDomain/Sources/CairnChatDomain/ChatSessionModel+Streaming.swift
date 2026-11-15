import Foundation

/// The stream drain for `ChatSessionModel`.
extension ChatSessionModel {

    func beginStreaming(assistantNodeID: UUID, provider: any InferenceProvider) {
        let params = conversation.params
        let history = ChatTree.visiblePath(nodes: nodes, activeLeafID: assistantNodeID)
        let request = GenerationRequest(
            modelID: selectedModelID,
            messages: ChatTree.messages(for: history, params: params),
            params: params
        )

        accumulator = StreamAccumulator()
        accumulator.begin()
        isBusy = true
        lastError = nil

        streamTask = Task {
            do {
                for try await chunk in provider.stream(request) {
                    try Task.checkCancellation()
                    accumulator.consume(chunk)
                    persist(assistantNodeID: assistantNodeID, state: accumulator.nodeState)
                }
                // A cancelled Task does not necessarily make AsyncThrowingStream throw:
                // cancellation can end the iteration cleanly, so we would otherwise mark
                // a truncated answer as a completed one. Check before declaring success.
                if Task.isCancelled || accumulator.phase == .cancelling {
                    accumulator.finishCancelled()
                    persist(assistantNodeID: assistantNodeID, state: .cancelled)
                } else {
                    accumulator.complete()
                    persist(assistantNodeID: assistantNodeID, state: .complete)
                }
            } catch is CancellationError {
                accumulator.finishCancelled()
                persist(assistantNodeID: assistantNodeID, state: .cancelled)
            } catch {
                accumulator.fail(error.localizedDescription)
                persist(assistantNodeID: assistantNodeID, state: .failed)
            }
            finishStreaming()
        }
    }

    /// Writes the partial turn on every chunk, so a cancel, a backgrounding, or a
    /// crash never throws away text the model already produced.
    func persist(assistantNodeID: UUID, state: NodeState) {
        guard let index = nodes.firstIndex(where: { $0.id == assistantNodeID }) else { return }
        var node = nodes[index]
        node.text = accumulator.text
        node.thinking = accumulator.hasReasoning ? accumulator.thinking : nil
        node.state = state
        node.metrics = accumulator.metrics
        nodes[index] = node

        do {
            try store.saveNode(node)
        } catch {
            lastError = error.localizedDescription
        }

        if path.contains(where: { $0.id == assistantNodeID }) {
            path = ChatTree.visiblePath(nodes: nodes, activeLeafID: conversation.activeLeafID)
        }
    }

    func finishStreaming() {
        isBusy = false
        streamTask = nil
    }

    static func makeTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? text
        return String(firstLine.prefix(48))
    }
}
