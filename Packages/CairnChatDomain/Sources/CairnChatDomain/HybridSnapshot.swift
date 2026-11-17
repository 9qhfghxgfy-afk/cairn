import Foundation

/// How far along a hybrid turn is.
public enum HybridStage: String, Sendable, Equatable {
    case candidates
    case synthesizing
    case finished
}

/// The live shape of a hybrid turn in flight — what the progress view renders, and nothing more.
///
/// A value type again, like `StreamAccumulator`, so the whole multi-candidate state of a turn can
/// be snapshotted and compared in a test without any provider running.
public struct HybridSnapshot: Sendable, Equatable {
    public var stage: HybridStage
    /// Kept in plan order, so the panels do not reshuffle as sides finish at different times.
    public var progress: [CandidateProgress]

    public init(stage: HybridStage = .candidates, progress: [CandidateProgress] = []) {
        self.stage = stage
        self.progress = progress
    }

    /// Every candidate starts as a named, waiting row — the panel never shows a blank panel.
    public static func starting(candidates: [HybridCandidate], labels: [String: String]) -> HybridSnapshot {
        HybridSnapshot(
            stage: .candidates,
            progress: candidates.enumerated().map { index, candidate in
                CandidateProgress(
                    order: index,
                    sourceLabel: labels[candidate.engineID] ?? candidate.engineID,
                    modelID: candidate.modelID
                )
            }
        )
    }

    public mutating func upsert(_ entry: CandidateProgress) {
        if let index = progress.firstIndex(where: { $0.order == entry.order }) {
            progress[index] = entry
        } else {
            progress.append(entry)
            progress.sort { $0.order < $1.order }
        }
    }

    /// Folds one engine event into the live state.
    public mutating func apply(_ event: HybridEvent) {
        switch event {
        case .candidateProgress(let entry):
            upsert(entry)
        case .draftUpdated(let draft):
            upsert(CandidateProgress(draft: draft, fallbackLabel: progress.first { $0.order == draft.order }?.sourceLabel ?? draft.sourceLabel))
        case .synthesisStarted:
            stage = .synthesizing
        case .synthesisChunk:
            break
        case .outcome(let result):
            stage = .finished
            for draft in result.drafts {
                upsert(CandidateProgress(draft: draft, fallbackLabel: progress.first { $0.order == draft.order }?.sourceLabel ?? draft.sourceLabel))
            }
        }
    }

    public var isSynthesizing: Bool { stage == .synthesizing }
    public var runningCount: Int { progress.filter { $0.isRunning }.count }
    public var anyRunning: Bool { runningCount > 0 || stage == .synthesizing }

    /// One line for the header: how many sides are still answering.
    public var summary: String {
        if stage == .synthesizing { return "synthesizing" }
        let total = progress.count
        let done = progress.filter { !$0.isRunning }.count
        if runningCount == 0 { return "\(done)/\(total) done" }
        return "\(runningCount) generating · \(done)/\(total) done"
    }
}

extension CandidateProgress {
    /// The same information a draft carries, in progress form.
    init(draft: CandidateDraft, fallbackLabel: String) {
        self.init(
            order: draft.order,
            sourceLabel: draft.sourceLabel.isEmpty ? fallbackLabel : draft.sourceLabel,
            modelID: draft.modelID,
            phase: CandidatePhase(draftState: draft.state),
            characters: draft.text.count,
            tokensPerSecond: draft.metrics?.tokensPerSecond,
            failure: draft.failure
        )
    }
}

extension CandidatePhase {
    init(draftState state: NodeState) {
        switch state {
        case .streaming: self = .streaming
        case .complete: self = .completed
        case .failed: self = .failed
        case .cancelled, .interrupted: self = .cancelled
        }
    }
}