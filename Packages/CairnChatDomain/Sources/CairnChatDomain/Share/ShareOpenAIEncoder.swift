import Foundation

/// Cairn's answer written in the OpenAI-compatible response shapes: SSE events for a streamed
/// turn, one object for a turn that did not ask to be streamed.
///
/// The frames are read back by this app's own OpenAI decoder in `ShareOpenAIEncoderTests`, which
/// is the proof that counts: the shape this phone writes is the shape this phone can read.
public enum ShareOpenAIEncoder {
    private struct Delta: Encodable {
        let content: String?
        let reasoningContent: String?
        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct Choice: Encodable {
        let index: Int
        let delta: Delta?
        let message: Message?
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case index, delta, message
            case finishReason = "finish_reason"
        }
    }

    private struct Usage: Encodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    private struct Chunk: Encodable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [Choice]
    }

    private struct Answer: Encodable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [Choice]
        let usage: Usage?
    }

    private struct ModelEntry: Encodable {
        let id: String
        let object: String
        let created: Int
        let ownedBy: String
        enum CodingKeys: String, CodingKey {
            case id, object, created
            case ownedBy = "owned_by"
        }
    }

    private struct ModelList: Encodable {
        let object: String
        let data: [ModelEntry]
    }

    /// An id a client can correlate a stream by. Cairn's own prefix so a log on the far machine
    /// says where the answer came from.
    public static func turnID() -> String { "chatcmpl-cairn-" + String(ShareToken.generate().prefix(12)) }

    public static func modelListBody(
        _ models: [ShareModelEntry],
        created: Int = ShareTimestamp.openAI()
    ) -> String {
        let list = ModelList(object: "list", data: models.map { entry in
            ModelEntry(id: entry.id, object: "model", created: created, ownedBy: ShareDialect.serverToken)
        })
        return ShareJSON.encode(list, fallback: "{\"object\":\"list\",\"data\":[]}")
    }

    public static func contentChunk(id: String, created: Int, model: String, text: String) -> String {
        ShareJSON.encode(
            Chunk(id: id, object: "chat.completion.chunk", created: created, model: model, choices: [Choice(index: 0, delta: Delta(content: text, reasoningContent: nil), message: nil, finishReason: nil)]),
            fallback: "{\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\"}"
        )
    }

    /// Reasoning is emitted only when the engine really produced some — under
    /// `reasoning_content`, the field reasoning-capable OpenAI-compatible servers use.
    public static func reasoningChunk(id: String, created: Int, model: String, text: String) -> String {
        ShareJSON.encode(
            Chunk(id: id, object: "chat.completion.chunk", created: created, model: model, choices: [Choice(index: 0, delta: Delta(content: nil, reasoningContent: text), message: nil, finishReason: nil)]),
            fallback: "{\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\"}"
        )
    }

    public static func finishChunk(id: String, created: Int, model: String, reason: FinishReason) -> String {
        ShareJSON.encode(
            Chunk(id: id, object: "chat.completion.chunk", created: created, model: model, choices: [Choice(index: 0, delta: Delta(content: nil, reasoningContent: nil), message: nil, finishReason: finishReasonName(reason))]),
            fallback: "{\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\"}"
        )
    }

    public static func answerBody(
        id: String,
        created: Int,
        model: String,
        text: String,
        reason: FinishReason,
        completionTokens: Int,
        promptTokens: Int?
    ) -> String {
        let total = (promptTokens ?? 0) + completionTokens
        let usage = Usage(promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: total)
        return ShareJSON.encode(
            Answer(id: id, object: "chat.completion", created: created, model: model, choices: [Choice(index: 0, delta: nil, message: Message(role: "assistant", content: text), finishReason: finishReasonName(reason))], usage: usage),
            fallback: "{\"id\":\"\(id)\",\"object\":\"chat.completion\"}"
        )
    }

    /// The published vocabulary is `stop`, `length`, `content_filter`, `tool_calls`. A cancelled or
    /// failed turn is named for what it was rather than reported as a finished answer.
    public static func finishReasonName(_ reason: FinishReason) -> String {
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
