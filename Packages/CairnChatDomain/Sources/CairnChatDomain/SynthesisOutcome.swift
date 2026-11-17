import Foundation

/// What the synthesizer stage produced — kept separate from the drafts it read, so a failed
/// synthesis is visible as a failed synthesis instead of looking like a short answer.
public struct SynthesisOutcome: Sendable, Equatable {
    public var text: String
    /// Non-nil only if the synthesizer itself emitted reasoning. Never carried over from a
    /// candidate's thinking.
    public var thinking: String?
    public var metrics: GenerationMetrics?
    public var state: NodeState
    public var failure: String?

    public init(
        text: String = "",
        thinking: String? = nil,
        metrics: GenerationMetrics? = nil,
        state: NodeState = .streaming,
        failure: String? = nil
    ) {
        self.text = text
        self.thinking = thinking
        self.metrics = metrics
        self.state = state
        self.failure = failure
    }

    public var answered: Bool { state == .complete && !text.isEmpty }
}