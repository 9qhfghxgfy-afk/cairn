import Foundation

/// The one thing the tool loop needs from a backend: stream one request.
///
/// A seam rather than `any InferenceProvider` so the loop is unit-testable against a scripted
/// engine — a turn is a *sequence* of streams, and a provider fake that answers every request the
/// same way cannot express "calls a tool, then answers". Nothing here knows about URLSession.
public struct ToolLoopEngine: Sendable {
    public var stream:
        @Sendable (GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error>

    public init(
        stream: @escaping @Sendable (GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error>
    ) {
        self.stream = stream
    }

    public static func from(_ provider: any InferenceProvider) -> ToolLoopEngine {
        ToolLoopEngine { request in provider.stream(request) }
    }
}

/// What the loop reports while it runs, so the composer can show a card per call rather than a
/// spinner, and so a cancelled turn still says which call it stopped on.
public enum ToolLoopEvent: Sendable, Equatable {
    case thinking(String)
    case content(String)
    case callStarted(ToolInvocation)
    case callFinished(ToolInvocation)
    case completed(ToolLoopOutcome)
}

/// The finished turn: one answer, its reasoning, its metrics, and the record of every call that fed
/// it. One node's worth of data — a tool turn is still one assistant node.
public struct ToolLoopOutcome: Sendable, Equatable {
    public var text: String
    public var thinking: String?
    public var metrics: GenerationMetrics?
    public var run: ToolRun

    public init(
        text: String,
        thinking: String? = nil,
        metrics: GenerationMetrics? = nil,
        run: ToolRun
    ) {
        self.text = text
        self.thinking = thinking
        self.metrics = metrics
        self.run = run
    }
}
