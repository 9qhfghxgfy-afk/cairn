import Foundation

/// Where one candidate stands right now, as the live panels see it.
public enum CandidatePhase: String, Sendable, Equatable, Codable {
    case queued
    case streaming
    case completed
    case failed
    case cancelled
}

/// One row of the Hybrid Parallel progress list. `Identifiable` by its plan order, so the
/// panels keep their left-to-right order no matter which side answers first.
public struct CandidateProgress: Sendable, Equatable, Identifiable {
    public var order: Int
    public var sourceLabel: String
    public var modelID: String
    public var phase: CandidatePhase
    /// Characters landed so far. A count, not content — progress must be cheap to publish and
    /// can never be a place prompt text gets copied.
    public var characters: Int
    /// This candidate's own measured tok/s, present only once it has emitted `.metrics`.
    public var tokensPerSecond: Double?
    public var failure: String?

    public init(
        order: Int,
        sourceLabel: String,
        modelID: String = "",
        phase: CandidatePhase = .queued,
        characters: Int = 0,
        tokensPerSecond: Double? = nil,
        failure: String? = nil
    ) {
        self.order = order
        self.sourceLabel = sourceLabel
        self.modelID = modelID
        self.phase = phase
        self.characters = characters
        self.tokensPerSecond = tokensPerSecond
        self.failure = failure
    }

    public var id: Int { order }

    public var isRunning: Bool { phase == .queued || phase == .streaming }

    /// One line for the progress row: what it is, and where it is.
    public var summary: String {
        switch phase {
        case .queued: return "waiting"
        case .streaming: return "streaming \(characters) chars"
        case .completed: return "done"
        case .failed: return failure ?? "failed"
        case .cancelled: return "stopped"
        }
    }
}