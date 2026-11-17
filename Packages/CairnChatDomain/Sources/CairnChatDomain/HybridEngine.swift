import Foundation

/// Runs one hybrid turn over the same `InferenceProvider.stream` every other turn already uses.
///
/// Candidates first — together when the residency rule allows it, one at a time with a release
/// between them when it does not — then the synthesizer. Nothing here is a second inference path,
/// and nothing is thrown away on the way out: a side that fails keeps its partial text and its
/// typed reason, while the sides that answered still stand.
public enum HybridEngine {

    private typealias Continuation = AsyncThrowingStream<HybridEvent, any Error>.Continuation

    public static func stream(_ job: HybridJob) -> AsyncThrowingStream<HybridEvent, any Error> {
        AsyncThrowingStream { continuation in
            let work = Task { await run(job, continuation: continuation) }
            // The consumer owns the turn. Dropping it cancels the work, which reaches every
            // in-flight candidate through the task group and the synthesis stage through its loop.
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func run(_ job: HybridJob, continuation: Continuation) async {
        let groups = HybridScheduling.candidateGroups(
            networkClasses: job.networkClasses,
            allowsTwoOnDeviceModelsResident: job.residency.allowsTwoOnDeviceModelsResident()
        )
        var collected: [Int: CandidateDraft] = [:]
        var ranOnDevice = false

        for (position, group) in groups.enumerated() {
            if group.concurrent && group.indexes.count > 1 {
                await withTaskGroup(of: (Int, CandidateDraft).self) { taskGroup in
                    for index in group.indexes {
                        taskGroup.addTask {
                            (index, await runCandidate(index: index, job: job, continuation: continuation))
                        }
                    }
                    for await (index, draft) in taskGroup { collected[index] = draft }
                }
            } else {
                for index in group.indexes {
                    collected[index] = await runCandidate(index: index, job: job, continuation: continuation)
                }
            }
            // A release between on-device runs is what makes "sequentially" mean something more
            // than two loads that happen to miss each other in time.
            if HybridScheduling.groupRanOnDevice(group, networkClasses: job.networkClasses) {
                ranOnDevice = true
                if position < groups.count - 1 { await job.residency.evictResidentModel() }
            }
            if Task.isCancelled { break }
        }

        let drafts = collected.values.sorted { $0.order < $1.order }
        var synthesis: SynthesisOutcome?
        if let synthesisJob = job.synthesis, !Task.isCancelled {
            if HybridScheduling.synthesisNeedsRelease(
                synthesizerClass: synthesisJob.networkClass,
                candidatesRanOnDevice: ranOnDevice
            ) {
                await job.residency.evictResidentModel()
            }
            // The synthesizer reads the drafts that actually ran, including the ones that
            // failed — a side that produced nothing is reported as nothing, not skipped.
            synthesis = await runSynthesis(synthesisJob, reading: drafts, continuation: continuation)
        }

        continuation.yield(.outcome(makeOutcome(job: job, drafts: drafts, synthesis: synthesis)))
        continuation.finish()
    }

    private static func runCandidate(index: Int, job: HybridJob, continuation: Continuation) async -> CandidateDraft {
        let candidate = job.candidates[index]
        var draft = CandidateDraft(
            order: index,
            sourceLabel: job.labels[candidate.engineID] ?? candidate.engineID,
            providerID: candidate.engineID,
            modelID: candidate.modelID,
            state: .streaming
        )
        guard let provider = job.provider(for: candidate), let request = job.request(at: index) else {
            draft.state = .failed
            draft.failure = "That engine is not registered right now, so this side never started."
            publish(draft, to: continuation)
            return draft
        }

        var acc = StreamAccumulator()
        acc.begin()
        publish(draft, to: continuation)
        do {
            for try await chunk in provider.stream(request) {
                acc.consume(chunk)
                draft.text = acc.text
                // Reasoning only ever comes from what this side actually emitted.
                draft.thinking = acc.hasReasoning ? acc.thinking : nil
                draft.metrics = acc.metrics
                publish(draft, to: continuation)
            }
            if Task.isCancelled {
                draft.state = .cancelled
            } else {
                acc.complete()
                draft.state = acc.nodeState
                if draft.state == .failed { draft.failure = acc.failure }
            }
        } catch is CancellationError {
            draft.state = .cancelled
        } catch {
            draft.state = .failed
            draft.failure = error.localizedDescription
        }
        publish(draft, to: continuation)
        return draft
    }

    private static func runSynthesis(
        _ job: HybridSynthesisJob,
        reading drafts: [CandidateDraft],
        continuation: Continuation
    ) async -> SynthesisOutcome {
        continuation.yield(.synthesisStarted)
        var acc = StreamAccumulator()
        acc.begin()
        do {
            for try await chunk in job.provider.stream(job.request(reading: drafts)) {
                acc.consume(chunk)
                // Passed through untouched: the unified answer is the synthesizer's own words.
                continuation.yield(.synthesisChunk(chunk))
            }
            if Task.isCancelled { return partialOutcome(acc, state: .cancelled) }
            acc.complete()
            return partialOutcome(acc, state: acc.nodeState)
        } catch is CancellationError {
            return partialOutcome(acc, state: .cancelled)
        } catch {
            return SynthesisOutcome(
                text: acc.text,
                thinking: acc.hasReasoning ? acc.thinking : nil,
                metrics: acc.metrics,
                state: .failed,
                failure: error.localizedDescription
            )
        }
    }

    private static func partialOutcome(_ acc: StreamAccumulator, state: NodeState) -> SynthesisOutcome {
        SynthesisOutcome(
            text: acc.text,
            thinking: acc.hasReasoning ? acc.thinking : nil,
            metrics: acc.metrics,
            state: state,
            failure: state == .failed ? acc.failure : nil
        )
    }

    private static func makeOutcome(
        job: HybridJob,
        drafts: [CandidateDraft],
        synthesis: SynthesisOutcome?
    ) -> HybridTurnOutcome {
        var provenance = HybridProvenance(
            mode: job.mode,
            candidateCount: job.candidates.count,
            failedCandidateCount: drafts.filter { $0.state == .failed }.count,
            synthesisRan: synthesis != nil
        )
        if let job = job.synthesis {
            provenance.synthesizerEngineID = job.candidate.engineID
            provenance.synthesizerModelID = job.candidate.modelID
            provenance.synthesisFailure = synthesis?.failure
        }
        return HybridTurnOutcome(
            drafts: drafts,
            synthesis: synthesis,
            provenance: provenance,
            wasCancelled: Task.isCancelled
        )
    }

    /// Publishes a draft and its progress row together, so the panels and the stored node can
    /// never disagree about how far a side has got.
    private static func publish(_ draft: CandidateDraft, to continuation: Continuation) {
        continuation.yield(.draftUpdated(draft))
        continuation.yield(
            .candidateProgress(CandidateProgress(draft: draft, fallbackLabel: draft.sourceLabel))
        )
    }
}