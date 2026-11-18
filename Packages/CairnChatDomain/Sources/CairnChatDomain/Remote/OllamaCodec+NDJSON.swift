import Foundation

extension OllamaCodec {
    // MARK: - NDJSON decoding

    struct WireChunk: Decodable {
        /// `message.tool_calls`: `arguments` is a JSON object on the documented wire, and a JSON
        /// string on some builds. Both are read, and neither is parsed here — the domain parses a
        /// call's arguments when it runs it, which is what keeps one odd blob one declined call.
        struct WireCall: Decodable {
            struct Function: Decodable {
                let name: String?
                let arguments: JSONValue?
            }
            let id: String?
            let function: Function?
        }

        struct Message: Decodable {
            let role: String?
            let content: String?
            let thinking: String?
            let toolCalls: [WireCall]?

            enum CodingKeys: String, CodingKey {
                case role, content, thinking
                case toolCalls = "tool_calls"
            }
        }
        let model: String?
        let message: Message?
        let response: String?
        let thinking: String?
        let done: Bool?
        let doneReason: String?
        let error: String?
        let evalCount: Int?
        let evalDuration: Int?
        let promptEvalCount: Int?

        enum CodingKeys: String, CodingKey {
            case model, message, response, thinking, done, error
            case doneReason = "done_reason"
            case evalCount = "eval_count"
            case evalDuration = "eval_duration"
            case promptEvalCount = "prompt_eval_count"
        }
    }

    /// Decodes one NDJSON line. Blank lines decode to no events; undecodable
    /// lines throw `.malformedLine` (never silently dropped mid-stream).
    public static func decodeNDJSONLine(_ line: Data) throws -> [Event] {
        if line.isEmpty { return [] }
        let chunk: WireChunk
        do {
            chunk = try JSONDecoder().decode(WireChunk.self, from: line)
        } catch {
            throw CodecError.malformedLine
        }
        if let serverError = chunk.error, !serverError.isEmpty {
            return [.error(serverError)]
        }
        var events: [Event] = []
        // /api/chat carries thinking under message.thinking (newer Ollama);
        // the legacy /api/generate shape has top-level response/thinking.
        if let reasoning = chunk.message?.thinking ?? chunk.thinking, !reasoning.isEmpty {
            events.append(.thinking(reasoning))
        }
        if let content = chunk.message?.content ?? chunk.response, !content.isEmpty {
            events.append(.content(content))
        }
        // Calls after content: a model that writes "let me check" and then calls a tool says the
        // sentence first, and the loop has to see the text before it runs anything.
        for (offset, call) in (chunk.message?.toolCalls ?? []).enumerated() {
            guard let name = call.function?.name, !name.isEmpty else { continue }
            events.append(.toolCall(ToolCallRequest(
                id: call.id ?? "ollama-call-\(offset + 1)",
                name: name,
                argumentsJSON: WireToolArguments.wireText(call.function?.arguments)
            )))
        }
        if chunk.done == true {
            events.append(.finished(
                FinalInfo(
                    evalCount: chunk.evalCount,
                    evalDurationMicros: chunk.evalDuration,
                    promptEvalCount: chunk.promptEvalCount,
                    doneReason: chunk.doneReason
                )
            ))
        }
        return events
    }
}
