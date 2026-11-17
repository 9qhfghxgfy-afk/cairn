import Foundation

/// The hybrid drain for `ChatSessionModel`: several engines, **one** assistant node, incremental
/// persistence the whole way, and a stop that reaches every side in flight.
extension ChatSessionModel {

    func beginHybridTurn(assistantNodeID: UUID) {
        guard let job = makeHybridJob(assistantNodeID: assistantNodeID) else {
            markHybridTurnFailed(assistantNodeID: assistantNodeID)
            return
        }
        hybrid = HybridSnapshot.starting(candidates: job.candidates, labels: job.labels)
        accumulator = StreamAccumulator()
        accumulator.begin()
        isBusy = true
        lastError = nil

        streamTask = Task {
            do {
                for try await event in HybridEngine.stream(job) {
                    try Task.checkCancellation()
                    apply(event, toAssistantNode: assistantNodeID)
                }
                // Same trap as the single-provider drain: cancellation can end iteration cleanly,
                // so success may not be assumed just because the loop finished.
                if Task.isCancelled { markHybridTurnCancelled(assistantNodeID: assistantNodeID) }
            } catch is CancellationError {
                markHybridTurnCancelled(assistantNodeID: assistantNodeID)
            } catch {
                // Candidate failures arrive as values, so reaching here means the drain itself
                // broke. Say so, and keep the drafts already stored.
                lastError = error.localizedDescription
                markHybridTurnFailed(assistantNodeID: assistantNodeID)
            }
            finishHybridTurn()
        }
    }

    private func apply(_ event: HybridEvent, toAssistantNode nodeID: UUID) {
        hybrid?.apply(event)
        switch event {
        case .candidateProgress, .synthesisStarted:
            break
        case .draftUpdated(let draft):
            writeDraft(draft, to: nodeID)
        case .synthesisChunk(let chunk):
            accumulator.consume(chunk)
            persistHybridBody(
                nodeID: nodeID,
                text: accumulator.text,
                thinking: accumulator.hasReasoning ? accumulator.thinking : nil,
                metrics: accumulator.metrics,
                state: accumulator.nodeState
            )
        case .outcome(let result):
            storeOutcome(result, on: nodeID)
        }
    }

    func firstFailureReason(in result: HybridTurnOutcome) -> String {
        if let reason = result.synthesis?.failure { return reason }
        if let reason = result.drafts.first(where: { $0.failure != nil })?.failure { return reason }
        return "Every candidate came back without an answer, so this turn has nothing to store."
    }

    /// Keeps the single-turn phase honest: the header's status pill means the same thing for a
    /// hybrid turn as it does for any other, and it is derived, never asserted.
    func mirrorPhase(_ state: NodeState) {
        switch state {
        case .complete: accumulator.complete()
        case .cancelled, .interrupted: accumulator.finishCancelled()
        case .failed: accumulator.fail(lastError ?? "This hybrid turn failed.")
        case .streaming: break
        }
    }

    private func markHybridTurnCancelled(assistantNodeID: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == assistantNodeID }) else { return }
        var node = nodes[index]
        node.state = .cancelled
        node.drafts = node.drafts.map { draft in
            draft.state == .complete ? draft : CandidateDraft(
                id: draft.id,
                order: draft.order,
                sourceLabel: draft.sourceLabel,
                providerID: draft.providerID,
                modelID: draft.modelID,
                text: draft.text,
                thinking: draft.thinking,
                state: draft.state == .streaming ? .cancelled : draft.state,
                metrics: draft.metrics,
                failure: draft.failure
            )
        }
        nodes[index] = node
        save(node)
        accumulator.finishCancelled()
        refreshPathIfNeeded(assistantNodeID)
    }

    private func markHybridTurnFailed(assistantNodeID: UUID) {
        guard let index = nodes.firstIndex(where: { $0.id == assistantNodeID }) else { return }
        var node = nodes[index]
        node.state = .failed
        nodes[index] = node
        save(node)
        accumulator.fail(lastError ?? "This hybrid turn could not start.")
        refreshPathIfNeeded(assistantNodeID)
    }

    private func finishHybridTurn() {
        hybrid?.stage = .finished
        finishStreaming()
    }
}