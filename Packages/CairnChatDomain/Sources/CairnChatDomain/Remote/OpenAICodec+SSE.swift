import Foundation

extension OpenAICodec {
    // MARK: - SSE decoding

    /// Extracts the payload of an SSE `data:` line; nil for comments, event
    /// names, ids, and blank separator lines.
    public static func sseDataPayload(fromLine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count)
        return payload.hasPrefix(" ") ? String(payload.dropFirst()) : String(payload)
    }

    struct WireChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoningContent: String?
                let reasoning: String?
                enum CodingKeys: String, CodingKey {
                    case content
                    case reasoningContent = "reasoning_content"
                    case reasoning
                }
            }
            let delta: Delta?
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        struct Usage: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?
            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
            }
        }
        struct WireError: Decodable { let message: String? }

        let choices: [Choice]?
        let usage: Usage?
        let error: WireError?
    }

    public static func finishReason(from raw: String?) -> FinishReason {
        switch raw {
        case "stop": return .stop
        case "length": return .length
        case "content_filter": return .contentFilter
        default: return .unknown
        }
    }

    /// Decodes one SSE `data:` payload. `"[DONE]"` → `.streamDone`.
    /// Reasoning arrives only as real `reasoning_content` / `reasoning`
    /// deltas — nothing is ever synthesized here.
    public static func decodeSSEPayload(_ payload: String) throws -> [Event] {
        if payload == "[DONE]" { return [.streamDone] }
        if payload.isEmpty { return [] }
        let chunk: WireChunk
        do {
            chunk = try JSONDecoder().decode(WireChunk.self, from: Data(payload.utf8))
        } catch {
            throw CodecError.malformedPayload
        }
        if let message = chunk.error?.message, !message.isEmpty {
            return [.error(message)]
        }
        var events: [Event] = []
        for choice in chunk.choices ?? [] {
            if let reasoning = choice.delta?.reasoningContent ?? choice.delta?.reasoning,
               !reasoning.isEmpty {
                events.append(.thinking(reasoning))
            }
            if let content = choice.delta?.content, !content.isEmpty {
                events.append(.content(content))
            }
            if let reason = choice.finishReason {
                events.append(.finished(finishReason(from: reason)))
            }
        }
        if let usage = chunk.usage {
            events.append(.usage(
                promptTokens: usage.promptTokens,
                completionTokens: usage.completionTokens
            ))
        }
        return events
    }
}
