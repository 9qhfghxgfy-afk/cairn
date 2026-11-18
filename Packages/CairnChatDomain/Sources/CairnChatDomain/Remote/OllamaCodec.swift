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
        case toolCall(ToolCallRequest)
        case finished(FinalInfo)
        case error(String)
    }

    // MARK: - Request encoding

    /// A call this assistant turn already made, sent back the way Ollama publishes it: `arguments` as
    /// an **object**, not as the JSON string the OpenAI dialect asks for. An unparseable blob goes out
    /// as `{}` rather than being dropped, because a call the server cannot see is a call the model
    /// will not remember making, and it will answer from the result it never got.
    private struct WireToolCall: Encodable {
        struct Function: Encodable { let name: String; let arguments: JSONValue }
        let id: String?
        let function: Function

        init(_ call: ToolCallRequest) {
            id = call.id.isEmpty ? nil : call.id
            function = Function(
                name: call.name,
                arguments: WireToolArguments.object(call.argumentsJSON)
            )
        }
    }

    private struct WireMessage: Encodable {
        let role: String
        let content: String
        let images: [String]?
        let toolCalls: [WireToolCall]?
        let toolCallID: String?

        enum CodingKeys: String, CodingKey {
            case role, content, images
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }
    }

    private struct WireRequest: Encodable {
        let model: String
        let messages: [WireMessage]
        let stream: Bool
        let think: Bool?
        /// nil when the user configured no knob this server accepts: an empty `options` object would
        /// be a claim that something was asked for.
        let options: SamplingFieldList?
        /// The tool schemas, present only on a turn that really offers them. The same rule as
        /// `options`: an empty `tools` array is a claim that the model was given something, so a
        /// tools-off request carries no `tools` key and no tool vocabulary at all.
        let tools: [WireToolSchema]?
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
            // A tool result is sent with the dialect's `tool` role while Cairn's own stored role
            // stays `.user`: the dialect's role is a wire detail about one message, not a fact about
            // the conversation, and inventing a `ChatRole` case would push a wire concern into every
            // stored node.
            let role = payload.isToolResult ? "tool" : payload.role.rawValue
            messages.append(WireMessage(
                role: role,
                content: payload.text,
                images: images,
                toolCalls: payload.toolCalls.isEmpty
                    ? nil : payload.toolCalls.map(WireToolCall.init),
                toolCallID: payload.toolCallID
            ))
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
            options: options.isEmpty ? nil : options,
            // Only a native turn carries schemas; a prompt-protocol turn was told the shapes in its
            // system block instead, and sending both is how a model emits a call twice.
            tools: request.toolProtocol == .native && !request.tools.isEmpty
                ? WireToolSchema.schemas(request.tools) : nil
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
