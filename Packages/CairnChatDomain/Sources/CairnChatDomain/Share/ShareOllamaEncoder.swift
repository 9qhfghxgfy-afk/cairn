import Foundation

/// Cairn's answer written in Ollama's published response shapes: NDJSON frames for a streamed
/// turn, one object for a turn that asked not to be streamed.
///
/// Every body here is produced by the domain's own decoder in `ShareOllamaCodecTests`, which is
/// the check that matters: a frame the app's Ollama **client** cannot read is a frame no Ollama
/// client can read either.
public enum ShareOllamaEncoder {
    private struct Message: Encodable {
        let role: String
        let content: String?
        let thinking: String?
    }

    private struct Chunk: Encodable {
        let model: String
        let createdAt: String
        let message: Message?
        let done: Bool
        let doneReason: String?
        let evalCount: Int?
        let evalDuration: Int?
        let promptEvalCount: Int?

        enum CodingKeys: String, CodingKey {
            case model
            case createdAt = "created_at"
            case message, done
            case doneReason = "done_reason"
            case evalCount = "eval_count"
            case evalDuration = "eval_duration"
            case promptEvalCount = "prompt_eval_count"
        }
    }

    private struct Detail: Encodable {
        let parameterSize: String?
        let quantizationLevel: String?
        enum CodingKeys: String, CodingKey {
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }

    private struct Model: Encodable {
        let name: String
        let model: String
        let details: Detail?
    }

    private struct ModelList: Encodable { let models: [Model] }
    private struct Version: Encodable { let version: String }

    public static func versionBody(_ version: String = ShareSettings.servedVersion) -> String {
        ShareJSON.encode(Version(version: version), fallback: "{\"version\":\"\"}")
    }

    public static func modelListBody(_ models: [ShareModelEntry]) -> String {
        let list = ModelList(models: models.map { entry in
            Model(
                name: entry.id,
                model: entry.id,
                details: (entry.parameterSize == nil && entry.quantization == nil)
                    ? nil
                    : Detail(parameterSize: entry.parameterSize, quantizationLevel: entry.quantization)
            )
        })
        return ShareJSON.encode(list, fallback: "{\"models\":[]}")
    }

    /// One streamed content frame. `done: false`, so a client keeps reading.
    public static func contentFrame(model: String, createdAt: String, text: String) -> String {
        ShareJSON.encode(
            Chunk(model: model, createdAt: createdAt, message: Message(role: "assistant", content: text, thinking: nil), done: false, doneReason: nil, evalCount: nil, evalDuration: nil, promptEvalCount: nil),
            fallback: "{\"model\":\"\(model)\",\"done\":false}"
        )
    }

    /// Reasoning goes out under `message.thinking` — the field newer Ollama builds use, and the
    /// one this app's own decoder reads. A turn whose engine emits no reasoning never calls this.
    public static func thinkingFrame(model: String, createdAt: String, text: String) -> String {
        ShareJSON.encode(
            Chunk(model: model, createdAt: createdAt, message: Message(role: "assistant", content: nil, thinking: text), done: false, doneReason: nil, evalCount: nil, evalDuration: nil, promptEvalCount: nil),
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
            Chunk(model: model, createdAt: createdAt, message: Message(role: "assistant", content: "", thinking: nil), done: true, doneReason: doneReason(reason), evalCount: evalCount, evalDuration: evalDurationMicros, promptEvalCount: promptEvalCount),
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
            Chunk(model: model, createdAt: createdAt, message: Message(role: "assistant", content: text, thinking: nil), done: true, doneReason: doneReason(reason), evalCount: evalCount, evalDuration: evalDurationMicros, promptEvalCount: promptEvalCount),
            fallback: "{\"model\":\"\(model)\",\"done\":true}"
        )
    }

    /// Ollama's own `done_reason` vocabulary: `stop` or `length`. Anything else the domain can
    /// observe — a cancelled or failed turn — is said plainly rather than mapped to `stop`, which
    /// would tell a client the answer finished when it did not.
    public static func doneReason(_ reason: FinishReason) -> String {
        switch reason {
        case .stop: return "stop"
        case .length: return "length"
        case .contentFilter: return "content_filter"
        case .cancelled: return "cancelled"
        case .error: return "error"
        case .unknown: return "stop"
        }
    }
}
