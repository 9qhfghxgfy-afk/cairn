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

    private struct WireRequest: Encodable {
        let model: String
        let messages: [WireMessage]
        let stream: Bool
        let think: Bool?
        /// nil when the user configured no knob this server accepts: an empty `options` object would
        /// be a claim that something was asked for.
        let options: SamplingFieldList?
    }

    /// Body for `POST /api/chat`. `think` is only sent for models whose metadata said they support
    /// it, and images only for vision-capable models.
    ///
    /// **The system prompt is not added here.** It arrives as the first entry of `request.messages`,
    /// assembled once by `ChatConfig.systemPrompt(in:turn:)`. An encoder that prepends one as well is
    /// what used to put two system messages on the wire.
    ///
    /// `support` is the active kind's sampling surface: a configured knob the server does not document
    /// is dropped rather than sent, because a key the server silently ignores is worse than one it
    /// rejects.
    public static func chatRequestBody(
        _ request: GenerationRequest,
        support: SamplingSupport,
        modelSupportsVision: Bool = false,
        thinking: Bool = false
    ) throws -> Data {
        var messages: [WireMessage] = []
        for payload in request.messages {
            var images: [String]? = nil
            if modelSupportsVision && !payload.imageData.isEmpty {
                images = payload.imageData.map { $0.base64EncodedString() }
            }
            messages.append(
                WireMessage(role: payload.role.rawValue, content: payload.text, images: images)
            )
        }
        let options = SamplingFieldList(
            sampling: request.config.sampling,
            support: support,
            dialect: .ollama
        )
        let wire = WireRequest(
            model: request.modelID,
            messages: messages,
            stream: true,
            think: thinking ? true : nil,
            options: options.isEmpty ? nil : options
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
