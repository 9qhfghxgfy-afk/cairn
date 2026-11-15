import Foundation

/// Why a generation stopped. Mirrors the finish reasons Cairn can observe across
/// Ollama, OpenAI-compatible servers, and on-device runtimes.
public enum FinishReason: String, Sendable, Equatable, Codable {
    case unknown
    case stop
    case length
    case cancelled
    case contentFilter
    case error
}

/// Measured, never estimated. Anything the backend did not report stays `nil`
/// rather than being guessed, because the UI surfaces these numbers directly.
public struct GenerationMetrics: Sendable, Equatable, Codable {
    public var tokensGenerated: Int
    public var promptTokens: Int?
    public var elapsedSeconds: Double
    public var timeToFirstTokenSeconds: Double?
    public var finishReason: FinishReason

    public init(
        tokensGenerated: Int,
        promptTokens: Int? = nil,
        elapsedSeconds: Double,
        timeToFirstTokenSeconds: Double? = nil,
        finishReason: FinishReason = .unknown
    ) {
        self.tokensGenerated = tokensGenerated
        self.promptTokens = promptTokens
        self.elapsedSeconds = elapsedSeconds
        self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        self.finishReason = finishReason
    }

    /// Live tok/s shown in the Hybrid Parallel panels.
    public var tokensPerSecond: Double? {
        guard elapsedSeconds > 0, tokensGenerated > 0 else { return nil }
        return Double(tokensGenerated) / elapsedSeconds
    }
}

/// A tool call requested by the model. Milestone 6 runs these through an
/// approval gate before anything is executed.
public struct ToolCallRequest: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Raw JSON exactly as the backend emitted it; parsed only after the user approves.
    public var argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// The single streaming vocabulary every provider speaks.
///
/// `.thinking` MUST only be produced when the backend genuinely emits a thinking
/// field or `<think>` tags. Cairn never synthesizes, paraphrases, or reconstructs
/// reasoning that a model did not actually output, and the reasoning panel in the
/// UI is rendered only when at least one `.thinking` chunk arrives.
public enum StreamChunk: Sendable, Equatable {
    case thinking(String)
    case content(String)
    case toolCall(ToolCallRequest)
    case metrics(GenerationMetrics)
}
