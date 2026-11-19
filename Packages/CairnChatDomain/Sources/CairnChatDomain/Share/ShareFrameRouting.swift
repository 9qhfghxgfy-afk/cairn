import Foundation

extension ShareFrame {
    /// One content piece, framed the way this route's clients read it: an Ollama line or an OpenAI
    /// SSE event. The framing is chosen here so a shape never has to be remembered at the call site.
    static func forShape(
        _ shape: ShareStreamShape,
        content: String,
        model: String,
        objectID: String,
        createdAt: String,
        createdUnix: Int
    ) -> String {
        switch shape {
        case .ollamaChat: return ndjson(ShareOllamaEncoder.contentFrame(model: model, createdAt: createdAt, text: content))
        case .ollamaGenerate: return ndjson(ShareOllamaGenerateEncoder.contentFrame(model: model, createdAt: createdAt, text: content))
        case .openAIChat: return sse(ShareOpenAIEncoder.contentChunk(id: objectID, created: createdUnix, model: model, text: content))
        case .openAICompletion: return sse(ShareOpenAICompletionEncoder.textChunk(id: objectID, created: createdUnix, model: model, text: content))
        }
    }

    /// Reasoning, framed. Only ever called for text an engine really emitted.
    static func forShape(
        _ shape: ShareStreamShape,
        thinking: String,
        model: String,
        objectID: String,
        createdAt: String,
        createdUnix: Int
    ) -> String {
        switch shape {
        case .ollamaChat: return ndjson(ShareOllamaEncoder.thinkingFrame(model: model, createdAt: createdAt, text: thinking))
        case .ollamaGenerate: return ndjson(ShareOllamaGenerateEncoder.thinkingFrame(model: model, createdAt: createdAt, text: thinking))
        case .openAIChat: return sse(ShareOpenAIEncoder.reasoningChunk(id: objectID, created: createdUnix, model: model, text: thinking))
        case .openAICompletion:
            // The legacy completion shape has nowhere to put reasoning, so a reasoning piece on that
            // route is dropped rather than written into the answer text, which would present a
            // model's private scratch as its reply.
            return ""
        }
    }

    /// The frames that end a turn: the closing object, and for the OpenAI dialect the sentinel a
    /// client reads as end-of-stream. Ollama has no sentinel — its closing object says `done: true`.
    static func closing(
        shape: ShareStreamShape,
        model: String,
        objectID: String,
        createdAt: String,
        createdUnix: Int,
        reason: FinishReason,
        metrics: GenerationMetrics?
    ) -> [String] {
        switch shape {
        case .ollamaChat:
            return [ndjson(ShareOllamaEncoder.finalFrame(model: model, createdAt: createdAt, reason: reason, evalCount: metrics?.tokensGenerated, evalDurationMicros: micros(metrics), promptEvalCount: metrics?.promptTokens))]
        case .ollamaGenerate:
            return [ndjson(ShareOllamaGenerateEncoder.finalFrame(model: model, createdAt: createdAt, reason: reason, evalCount: metrics?.tokensGenerated, evalDurationMicros: micros(metrics), promptEvalCount: metrics?.promptTokens))]
        case .openAIChat:
            return [sse(ShareOpenAIEncoder.finishChunk(id: objectID, created: createdUnix, model: model, reason: reason)), sseDone]
        case .openAICompletion:
            return [sse(ShareOpenAICompletionEncoder.finishChunk(id: objectID, created: createdUnix, model: model, reason: reason)), sseDone]
        }
    }

    /// Microseconds from the engine's own elapsed measurement; nothing is measured here.
    private static func micros(_ metrics: GenerationMetrics?) -> Int? {
        guard let metrics else { return nil }
        return Int(metrics.elapsedSeconds * 1_000_000)
    }
}
