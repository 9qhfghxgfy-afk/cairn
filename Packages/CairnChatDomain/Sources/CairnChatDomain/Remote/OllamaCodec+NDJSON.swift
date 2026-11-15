import Foundation

extension OllamaCodec {
    // MARK: - NDJSON decoding

    struct WireChunk: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
            let thinking: String?
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
