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
            /// One streamed call fragment. `arguments` is the piece of a JSON blob this chunk
            /// carried — the whole blob is only complete when the choice finishes, which is why the
            /// fragments are stitched in the pipeline rather than decoded here.
            struct CallFragment: Decodable {
                struct Function: Decodable {
                    let name: String?
                    let arguments: String?
                }
                let index: Int?
                let id: String?
                let type: String?
                let function: Function?
            }
            struct Delta: Decodable {
                let content: String?
                let reasoningContent: String?
                let reasoning: String?
                let toolCalls: [CallFragment]?
                enum CodingKeys: String, CodingKey {
                    case content
                    case reasoningContent = "reasoning_content"
                    case reasoning
                    case toolCalls = "tool_calls"
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
        // A reply that stopped in order to call a tool stopped on purpose. The loop decides what
        // happens next; recording it as `.unknown` would tell the user the server ended for a reason
        // nobody could name.
        case "tool_calls", "function_call": return .stop
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
            // Fragments, not calls: the id and name arrive in one chunk and the arguments are split
            // across the ones after it, so nothing here can know a call is finished.
            for (position, fragment) in (choice.delta?.toolCalls ?? []).enumerated() {
                let name = fragment.function?.name ?? ""
                let arguments = fragment.function?.arguments ?? ""
                guard !name.isEmpty || !arguments.isEmpty else { continue }
                events.append(.toolCallDelta(
                    index: fragment.index ?? position,
                    id: fragment.id,
                    name: name.isEmpty ? nil : name,
                    arguments: arguments
                ))
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
