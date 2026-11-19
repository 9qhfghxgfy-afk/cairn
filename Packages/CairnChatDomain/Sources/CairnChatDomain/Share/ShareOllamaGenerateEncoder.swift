import Foundation

/// `/api/generate` answers in a different object than `/api/chat`: the text is at the top level as
/// `response`, and reasoning at the top level as `thinking`, with no `message` wrapper.
///
/// Reusing the chat shape here is the classic share-surface bug — the server streams, the client
/// reads `response`, finds nothing, and reports an empty model. Frames are read back by this app's
/// own Ollama decoder in `ShareGenerateEncoderTests`, which reads both shapes.
public enum ShareOllamaGenerateEncoder {
    private struct Chunk: Encodable {
        let model: String
        let createdAt: String
        let response: String?
        let thinking: String?
        let done: Bool
        let doneReason: String?
        let evalCount: Int?
        let evalDuration: Int?
        let promptEvalCount: Int?

        enum CodingKeys: String, CodingKey {
            case model, response, thinking, done
            case createdAt = "created_at"
            case doneReason = "done_reason"
            case evalCount = "eval_count"
            case evalDuration = "eval_duration"
            case promptEvalCount = "prompt_eval_count"
        }
    }

    public static func contentFrame(model: String, createdAt: String, text: String) -> String {
        ShareJSON.encode(
            Chunk(model: model, createdAt: createdAt, response: text, thinking: nil, done: false, doneReason: nil, evalCount: nil, evalDuration: nil, promptEvalCount: nil),
            fallback: "{\"model\":\"\(model)\",\"done\":false}"
        )
    }

    /// Reasoning only ever goes out because an engine really emitted it; nothing here makes a model
    /// reason, and a turn with no thinking field never calls this.
    public static func thinkingFrame(model: String, createdAt: String, text: String) -> String {
        ShareJSON.encode(
            Chunk(model: model, createdAt: createdAt, response: nil, thinking: text, done: false, doneReason: nil, evalCount: nil, evalDuration: nil, promptEvalCount: nil),
            fallback: "{\"model\":\"\(model)\",\"done\":false}"
        )
    }

    public static func finalFrame(
        model: String,
        createdAt: String,
        reason: FinishReason,
        evalCount: Int?,
        evalDurationMicros: Int?,
        promptEvalCount: Int?
    ) -> String {
        ShareJSON.encode(
            Chunk(model: model, createdAt: createdAt, response: "", thinking: nil, done: true, doneReason: ShareOllamaEncoder.doneReason(reason), evalCount: evalCount, evalDuration: evalDurationMicros, promptEvalCount: promptEvalCount),
            fallback: "{\"model\":\"\(model)\",\"done\":true}"
        )
    }

    /// A non-streamed turn: one object, whole answer, `done: true`.
    public static func answerBody(
        model: String,
        createdAt: String,
        text: String,
        reason: FinishReason,
        evalCount: Int?,
        evalDurationMicros: Int?,
        promptEvalCount: Int?
    ) -> String {
        ShareJSON.encode(
            Chunk(model: model, createdAt: createdAt, response: text, thinking: nil, done: true, doneReason: ShareOllamaEncoder.doneReason(reason), evalCount: evalCount, evalDuration: evalDurationMicros, promptEvalCount: promptEvalCount),
            fallback: "{\"model\":\"\(model)\",\"done\":true}"
        )
    }
}
