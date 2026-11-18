import Foundation

/// The multi-step turn drain for `ChatSessionModel`.
///
/// This mirrors the plain stream drain in `ChatSessionModel+Streaming.swift` on purpose: the same
/// accumulator, the same write-on-every-chunk persistence, the same "cancellation may end the stream
/// cleanly, so check before declaring success" rule. A tool turn must not become a second, separate
/// implementation of *save what the model said so far* — that is how a cancelled turn loses its text.
extension ChatSessionModel {

    func beginToolTurn(assistantNodeID: UUID, provider: any InferenceProvider) {
        let history = ChatTree.visiblePath(nodes: nodes, activeLeafID: assistantNodeID)
        let selection = toolSelection(for: provider)
        let format = toolRouting(for: provider).format
        let offered = ToolPromptBlock.names(selection.definitions)
        let request = GenerationRequest(
            modelID: selectedModelID,
            messages: ChatTree.messages(
                for: history,
                systemPrompt: systemPrompt(for: provider, selection: selection, format: format)
            ),
            config: conversation.config,
            tools: selection.definitions,
            toolProtocol: format
        )

        accumulator = StreamAccumulator()
        accumulator.begin()
        liveToolRun = ToolRun(protocolUsed: format)
        isBusy = true
        lastError = nil

        streamTask = Task {
            var settled = false
            do {
                let events = ToolLoop.stream(
                    request: request,
                    engine: ToolLoopEngine.from(provider),
                    registry: toolRegistry,
                    format: format,
                    policy: toolPolicy,
                    context: .forTurn(toolsEnabled: true)
                )
                for try await event in events {
                    try Task.checkCancellation()
                    switch event {
                    case .thinking(let piece): accumulator.consume(.thinking(piece))
                    case .content(let piece): accumulator.consume(.content(piece))
                    case .callStarted(let call): record(call, assistantNodeID: assistantNodeID, offered: offered)
                    case .callFinished(let call): record(call, assistantNodeID: assistantNodeID, offered: offered)
                    case .completed(let outcome):
                        settle(
                            assistantNodeID: assistantNodeID, outcome: outcome,
                            offered: offered, state: .complete
                        )
                        settled = true
                    }
                }
                if !settled { settleInterrupted(assistantNodeID: assistantNodeID, offered: offered, format: format) }
            } catch is CancellationError {
                accumulator.finishCancelled()
                settle(
                    assistantNodeID: assistantNodeID,
                    outcome: ToolLoopOutcome(text: accumulator.text, run: partialRun(format)),
                    offered: offered, state: .cancelled
                )
            } catch {
                accumulator.fail(error.localizedDescription)
                settle(
                    assistantNodeID: assistantNodeID,
                    outcome: ToolLoopOutcome(text: accumulator.text, run: partialRun(format)),
                    offered: offered, state: .failed
                )
            }
            liveToolRun = nil
            finishStreaming()
        }
    }

    /// A turn that ended without an outcome — cancelled, or a stream that simply stopped. Whatever the
    /// model had said stands, with the calls that fed it, and the state says so.
    private func settleInterrupted(assistantNodeID: UUID, offered: [String], format: ToolCallingProtocol) {
        accumulator.finishCancelled()
        settle(
            assistantNodeID: assistantNodeID,
            outcome: ToolLoopOutcome(text: accumulator.text, run: partialRun(format)),
            offered: offered, state: .cancelled
        )
    }

    /// The calls gathered so far, so a stopped turn still shows what it was doing.
    private func partialRun(_ format: ToolCallingProtocol) -> ToolRun {
        liveToolRun ?? ToolRun(protocolUsed: format)
    }

    private func record(
        _ call: ToolInvocation, assistantNodeID: UUID, offered: [String]
    ) {
        liveToolRun?.record(call)
        guard let run = liveToolRun,
              let index = nodes.firstIndex(where: { $0.id == assistantNodeID })
        else { return }
        var node = nodes[index]
        node.toolRun = run
        node.toolsOffered = offered
        nodes[index] = node
        // Written whole, in one column, exactly as `provenance` is: a card that exists only in memory
        // would vanish on a relaunch, and a call the user can no longer see is a call they cannot
        // audit.
        try? store.saveNode(node)
    }

    /// The one write that closes a tool turn: text, reasoning, metrics, the call record and the node
    /// state together, so a card cannot outlive its turn and a truncated answer cannot be marked
    /// complete.
    func settle(
        assistantNodeID: UUID,
        outcome: ToolLoopOutcome,
        offered: [String],
        state: NodeState
    ) {
        guard let index = nodes.firstIndex(where: { $0.id == assistantNodeID }) else { return }
        var node = nodes[index]
        node.text = outcome.text.isEmpty ? accumulator.text : outcome.text
        node.thinking = outcome.thinking ?? (accumulator.hasReasoning ? accumulator.thinking : nil)
        node.state = state
        node.metrics = outcome.metrics ?? accumulator.metrics
        node.toolRun = outcome.run.isEmpty ? nil : outcome.run
        node.toolsOffered = offered
        nodes[index] = node
        do {
            try store.saveNode(node)
        } catch {
            lastError = error.localizedDescription
        }
        path = ChatTree.visiblePath(nodes: nodes, activeLeafID: conversation.activeLeafID)
    }
}
