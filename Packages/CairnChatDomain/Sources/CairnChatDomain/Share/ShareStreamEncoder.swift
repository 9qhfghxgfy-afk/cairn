import Foundation

/// One engine stream, translated into the frames one published dialect expects.
///
/// This is the whole contract of the share surface in one type, and it is pure so the contract is
/// testable with no socket:
/// - a content piece goes out **immediately** as one frame, because a shared turn that arrives all
///   at the end is not a stream whatever the content type says;
/// - reasoning is forwarded **only** when the engine emitted it — nothing here makes a model think;
/// - counts are copied from the engine's own metrics or left absent. A zero is never written where
///   a measurement is missing, because a client will report it as a fact about the model;
/// - a tool call is dropped rather than forwarded: a shared turn offers no tools, so a stranger's
///   conversation is never armed with this phone's.
public struct ShareStreamEncoder: Sendable {
    public let shape: ShareStreamShape
    public let model: String
    private let objectID: String
    private let createdAt: String
    private let createdUnix: Int
    private(set) public var wholeText: String = ""
    private var metrics: GenerationMetrics?
    private var closed = false

    public init(shape: ShareStreamShape, model: String, started: Date = Date()) {
        self.shape = shape
        self.model = model
        switch shape {
        case .ollamaChat, .ollamaGenerate: objectID = ""
        case .openAIChat: objectID = ShareOpenAIEncoder.turnID()
        case .openAICompletion: objectID = ShareOpenAICompletionEncoder.completionID()
        }
        self.createdAt = ShareTimestamp.ollama(started)
        self.createdUnix = ShareTimestamp.openAI(started)
    }

    /// Frames to write for one chunk, in order. Empty means "nothing goes out for this chunk".
    public mutating func append(_ chunk: StreamChunk) -> [String] {
        switch chunk {
        case .content(let piece):
            wholeText += piece
            guard !piece.isEmpty else { return [] }
            return [ShareFrame.forShape(shape, content: piece, model: model, objectID: objectID, createdAt: createdAt, createdUnix: createdUnix)]
        case .thinking(let piece):
            guard !piece.isEmpty else { return [] }
            let frame = ShareFrame.forShape(shape, thinking: piece, model: model, objectID: objectID, createdAt: createdAt, createdUnix: createdUnix)
            // A dialect with nowhere to put reasoning drops the piece; an empty frame would be a
            // heartbeat with nothing in it.
            return frame.isEmpty ? [] : [frame]
        case .toolCall:
            return []
        case .metrics(let reported):
            metrics = reported
            return []
        }
    }

    /// The closing frames. The reason is passed in by whoever ran the stream, because only that code
    /// knows whether the turn finished, was cancelled, or failed; an engine's own reported reason
    /// wins over the passed one when the engine reported one.
    public mutating func finish(reason: FinishReason) -> [String] {
        guard !closed else { return [] }
        closed = true
        let observed = metrics?.finishReason ?? reason
        return ShareFrame.closing(
            shape: shape, model: model, objectID: objectID, createdAt: createdAt, createdUnix: createdUnix,
            reason: observed, metrics: metrics
        )
    }

    /// A whole answer for a body that said `"stream": false` — one object, no frames, and the
    /// content type of a normal JSON response.
    public func bufferedReply() -> ShareReply {
        let reason = metrics?.finishReason ?? .unknown
        switch shape {
        case .ollamaChat:
            return ShareHTTPResponse.json(status: 200, body: ShareOllamaEncoder.answerBody(model: model, createdAt: createdAt, text: wholeText, reason: reason, evalCount: metrics?.tokensGenerated, evalDurationMicros: elapsedMicros, promptEvalCount: metrics?.promptTokens))
        case .ollamaGenerate:
            return ShareHTTPResponse.json(status: 200, body: ShareOllamaGenerateEncoder.answerBody(model: model, createdAt: createdAt, text: wholeText, reason: reason, evalCount: metrics?.tokensGenerated, evalDurationMicros: elapsedMicros, promptEvalCount: metrics?.promptTokens))
        case .openAIChat:
            return ShareHTTPResponse.json(status: 200, body: ShareOpenAIEncoder.answerBody(id: objectID, created: createdUnix, model: model, text: wholeText, reason: reason, completionTokens: metrics?.tokensGenerated, promptTokens: metrics?.promptTokens), contentType: shape.dialect.contentType)
        case .openAICompletion:
            return ShareHTTPResponse.json(status: 200, body: ShareOpenAICompletionEncoder.answerBody(id: objectID, created: createdUnix, model: model, text: wholeText, reason: reason, completionTokens: metrics?.tokensGenerated, promptTokens: metrics?.promptTokens), contentType: shape.dialect.contentType)
        }
    }

    /// A stream head written before the first frame, so a client starts reading in stream mode
    /// rather than waiting for a body length it will never be given.
    public var streamReply: ShareReply { ShareReply(status: 200, contentType: shape.dialect.streamContentType, streaming: true) }

    /// Microseconds from the engine's own elapsed measurement, never from a clock of our own.
    private var elapsedMicros: Int? {
        guard let metrics else { return nil }
        return Int(metrics.elapsedSeconds * 1_000_000)
    }
}
