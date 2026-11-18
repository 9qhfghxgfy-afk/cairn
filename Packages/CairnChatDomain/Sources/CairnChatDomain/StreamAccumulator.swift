import Foundation

/// Lifecycle of one generation. Deliberately a value type so the whole streaming
/// state of a turn can be snapshotted, compared, and unit-tested without a provider.
public enum GenerationPhase: String, Sendable, Equatable {
    case idle
    case preparing
    case thinking
    case streaming
    case cancelling
    case completed
    case cancelled
    case failed
}

/// Reduces `StreamChunk`s into the text, reasoning, tool calls, and metrics of one
/// turn. The UI derives every panel from this, and `.thinking` only ever appears if
/// a provider actually produced it.
public struct StreamAccumulator: Sendable, Equatable {
    public private(set) var thinking: String = ""
    public private(set) var content: String = ""
    public private(set) var toolCalls: [ToolCallRequest] = []
    public private(set) var metrics: GenerationMetrics?
    public private(set) var phase: GenerationPhase = .idle
    public private(set) var failure: String?

    public init() {}

    public var hasReasoning: Bool { !thinking.isEmpty }
    public var isEmpty: Bool { content.isEmpty && thinking.isEmpty }
    public var text: String { content }

    public mutating func begin() {
        phase = .preparing
    }

    /// Starts a turn that **carries** text already written.
    ///
    /// Continue Generation streams only what comes after the cut-off point, while the node it writes must
    /// read as one answer rather than a second half. The carried text is therefore the accumulator's
    /// starting content, so every partial write and the final one both carry the whole answer, and a
    /// stop half-way through still leaves a complete, longer answer on the node.
    public mutating func begin(carrying prefix: String) {
        content = prefix
        phase = .preparing
    }

    public mutating func consume(_ chunk: StreamChunk) {
        switch chunk {
        case .thinking(let fragment):
            thinking += fragment
            phase = .thinking
        case .content(let fragment):
            content += fragment
            phase = .streaming
        case .toolCall(let call):
            toolCalls.append(call)
            phase = .streaming
        case .metrics(let received):
            metrics = received
        }
    }

    public mutating func complete() {
        phase = .completed
    }

    /// User pressed stop: keep the partial text, flip to `.cancelling` until the
    /// stream actually terminates so the button cannot be double-tapped into a limbo.
    public mutating func requestCancellation() {
        guard phase == .preparing || phase == .thinking || phase == .streaming else { return }
        phase = .cancelling
    }

    public mutating func finishCancelled() {
        phase = .cancelled
    }

    public mutating func fail(_ description: String) {
        failure = description
        phase = .failed
    }

    public var nodeState: NodeState {
        switch phase {
        case .idle, .preparing, .thinking, .streaming, .cancelling: return .streaming
        case .completed: return .complete
        case .cancelled: return .cancelled
        case .failed: return .failed
        }
    }
}
