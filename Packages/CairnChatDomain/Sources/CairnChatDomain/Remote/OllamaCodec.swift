import Foundation

/// Pure Ollama HTTP API codec (public, documented wire format). No networking
/// here: bytes in, values out — so all of it is unit-testable on the macOS host.
public enum OllamaCodec: Sendable {
    public enum CodecError: Error, Equatable, Sendable {
        case malformedLine
    }

    /// What the final NDJSON chunk reported. Missing stays nil — never guessed.
    public struct FinalInfo: Sendable, Equatable {
        public var evalCount: Int?
        public var evalDurationMicros: Int?
        public var promptEvalCount: Int?
        public var doneReason: String?

        public init(
            evalCount: Int? = nil,
            evalDurationMicros: Int? = nil,
            promptEvalCount: Int? = nil,
            doneReason: String? = nil
        ) {
            self.evalCount = evalCount
            self.evalDurationMicros = evalDurationMicros
            self.promptEvalCount = promptEvalCount
            self.doneReason = doneReason
        }
    }

    public enum Event: Sendable, Equatable {
        case thinking(String)
        case content(String)
        case finished(FinalInfo)
        case error(String)
    }

    // MARK: - Request encoding

    private struct WireMessage: Encodable {
        let role: String
        let content: String
        let images: [String]?
    }

    private struct WireOptions: Encodable {
        let temperature: Double
        let topP: Double
        let numPredict: Int
        let numCtx: Int
        enum CodingKeys: String, CodingKey {
            case temperature
            case topP = "top_p"
            case numPredict = "num_predict"
            case numCtx = "num_ctx"
        }
    }

    private struct WireRequest: Encodable {
        let model: String
        let messages: [WireMessage]
        let stream: Bool
        let think: Bool?
        let options: WireOptions
    }

    /// Body for `POST /api/chat`. `think` is only sent for models whose
    /// metadata said they support it; images only for vision-capable models.
    public static func chatRequestBody(
        _ request: GenerationRequest,
        modelSupportsVision: Bool = false,
        thinking: Bool = false
    ) throws -> Data {
        var messages: [WireMessage] = []
        let system = request.params.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            messages.append(WireMessage(role: "system", content: system, images: nil))
        }
        for payload in request.messages {
            var images: [String]? = nil
            if modelSupportsVision && !payload.imageData.isEmpty {
                images = payload.imageData.map { $0.base64EncodedString() }
            }
            messages.append(
                WireMessage(role: payload.role.rawValue, content: payload.text, images: images)
            )
        }
        let wire = WireRequest(
            model: request.modelID,
            messages: messages,
            stream: true,
            think: thinking ? true : nil,
            options: WireOptions(
                temperature: request.params.temperature,
                topP: request.params.topP,
                numPredict: request.params.maxTokens,
                numCtx: request.params.contextWindow
            )
        )
        return try JSONEncoder().encode(wire)
    }

    /// Metrics only when the server actually reported token counts; elapsed
    /// and time-to-first-token are measured by the caller, not invented here.
    public static func metrics(
        from info: FinalInfo,
        elapsedSeconds: Double,
        timeToFirstTokenSeconds: Double?,
        finishReason: FinishReason = .stop
    ) -> GenerationMetrics? {
        guard let tokens = info.evalCount, tokens > 0 else { return nil }
        return GenerationMetrics(
            tokensGenerated: tokens,
            promptTokens: info.promptEvalCount,
            elapsedSeconds: elapsedSeconds,
            timeToFirstTokenSeconds: timeToFirstTokenSeconds,
            finishReason: finishReason
        )
    }
}
