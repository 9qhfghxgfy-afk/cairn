import Foundation

/// The legacy `/v1/completions` shape, which is **not** the chat shape: the text is
/// `choices[].text`, there is no `delta`, and the object is `text_completion`.
///
/// Kept separate from `ShareOpenAIEncoder` on purpose. A completion client reading
/// `choices[].delta.content` reads nothing, and the failure looks like a model that answers with an
/// empty string rather than a server that used the wrong field. This shape is asserted against the
/// published field names in `ShareCompletionEncoderTests`; this app's own client only ever speaks
/// the chat shape, so it has no legacy reader to round-trip through.
public enum ShareOpenAICompletionEncoder {
    private struct Choice: Encodable {
        let index: Int
        let text: String?
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case index, text
            case finishReason = "finish_reason"
        }
    }

    private struct Chunk: Encodable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [Choice]
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

    private struct Answer: Encodable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [Choice]
        let usage: Usage?
    }

    public static func completionID() -> String { "cmpl-cairn-" + String(ShareToken.generate().prefix(12)) }

    public static func textChunk(id: String, created: Int, model: String, text: String) -> String {
        ShareJSON.encode(
            Chunk(id: id, object: "text_completion", created: created, model: model, choices: [Choice(index: 0, text: text, finishReason: nil)]),
            fallback: "{\"id\":\"\(id)\",\"object\":\"text_completion\"}"
        )
    }

    public static func finishChunk(id: String, created: Int, model: String, reason: FinishReason) -> String {
        ShareJSON.encode(
            Chunk(id: id, object: "text_completion", created: created, model: model, choices: [Choice(index: 0, text: nil, finishReason: ShareOpenAIEncoder.finishReasonName(reason))]),
            fallback: "{\"id\":\"\(id)\",\"object\":\"text_completion\"}"
        )
    }

    public static func answerBody(
        id: String,
        created: Int,
        model: String,
        text: String,
        reason: FinishReason,
        completionTokens: Int?,
        promptTokens: Int?
    ) -> String {
        let total: Int? = (promptTokens != nil && completionTokens != nil) ? (promptTokens ?? 0) + (completionTokens ?? 0) : nil
        let usage = Usage(promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: total)
        return ShareJSON.encode(
            Answer(id: id, object: "text_completion", created: created, model: model, choices: [Choice(index: 0, text: text, finishReason: ShareOpenAIEncoder.finishReasonName(reason))], usage: usage),
            fallback: "{\"id\":\"\(id)\",\"object\":\"text_completion\"}"
        )
    }
}
