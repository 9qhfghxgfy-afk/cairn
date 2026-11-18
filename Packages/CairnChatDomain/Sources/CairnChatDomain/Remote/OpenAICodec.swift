import Foundation

/// Pure OpenAI-compatible codec (`/v1/chat/completions` SSE, `/v1/models`).
/// Covers LM Studio and any server speaking the same public wire format.
public enum OpenAICodec: Sendable {
    public enum CodecError: Error, Equatable, Sendable {
        case malformedPayload
    }

    public enum Event: Sendable, Equatable {
        case thinking(String)
        case content(String)
        /// One fragment of a call: this dialect streams `tool_calls` as pieces — the id and name in
        /// one chunk, the arguments split across the next ones. They are stitched back into a whole
        /// call by `RemoteChatPipeline`, which is the only place that knows a call has ended.
        case toolCallDelta(index: Int, id: String?, name: String?, arguments: String)
        case usage(promptTokens: Int?, completionTokens: Int?)
        case finished(FinishReason)
        case streamDone
        case error(String)
    }

    // MARK: - Request encoding

    /// A call this assistant turn made, sent back the way this dialect publishes it: `arguments` as a
    /// JSON **string**, which is the opposite of Ollama's object form. An object here is how a strict
    /// server rejects the whole turn rather than one call.
    private struct WireToolCall: Encodable {
        struct Function: Encodable { let name: String; let arguments: String }
        let id: String?
        let type: String
        let function: Function

        init(_ call: ToolCallRequest) {
            id = call.id.isEmpty ? nil : call.id
            type = "function"
            function = Function(
                name: call.name,
                arguments: WireToolArguments.text(call.argumentsJSON)
            )
        }
    }

    private struct WireContentPart: Encodable {
        let type: String
        let text: String?
        let imageURL: WireImageURL?
        struct WireImageURL: Encodable { let url: String }

        // The wire key is `image_url`; without this mapping the synthesized key
        // would be `imageURL`, which every OpenAI-compatible server ignores.
        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }
    }

    private struct WireMessage: Encodable {
        let role: String
        // String OR [parts] — OpenAI multimodal convention.
        let text: String?
        let parts: [WireContentPart]?
        let images: [String]? // unused; kept simple via parts
        /// The calls of an assistant turn that asked for them, and the id a tool result answers.
        /// Both are absent on every message written before P3, which is what keeps an old
        /// conversation byte-identical on the wire.
        let toolCalls: [WireToolCall]?
        let toolCallID: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            // A tool result carries the dialect's `tool` role plus the id it answers; Cairn's stored
            // role stays `.user`, because a wire role for one message is not a fact about the
            // conversation and a new `ChatRole` case would put a wire concern into every stored node.
            try container.encode(
                toolCallID == nil ? role : "tool", forKey: .role
            )
            if let parts {
                try container.encode(parts, forKey: .content)
            } else {
                try container.encode(text ?? "", forKey: .content)
            }
            if let toolCalls, !toolCalls.isEmpty {
                try container.encode(toolCalls, forKey: .toolCalls)
            }
            if let toolCallID {
                try container.encode(toolCallID, forKey: .toolCallID)
            }
        }
    }

    private struct WireRequest: Encodable {
        let model: String
        let messages: [WireMessage]
        let stream: Bool
        let streamOptions: StreamOptions?
        /// Sampling at the top level of the request, already filtered to what this server documents.
        let sampling: SamplingFieldList
        /// The tool schemas, present only on a turn that really offers them — the same rule as the
        /// sampling keys, so a tools-off request carries no `tools` key at all.
        let tools: [WireToolSchema]?

        struct StreamOptions: Encodable {
            let includeUsage: Bool

            // `stream_options.include_usage` is the field the server needs to send a
            // final usage chunk; a camelCase key would be accepted and then ignored,
            // which is worse than an error - metrics would silently stay nil.
            enum CodingKeys: String, CodingKey {
                case includeUsage = "include_usage"
            }
        }

        /// Hand-written rather than synthesised, because the sampling keys are decided at run time by
        /// the capability table and a synthesised container can only write keys known at compile time.
        /// The keys land at the top level, where the OpenAI schema says they belong.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            try container.encode(model, forKey: DynamicCodingKey(stringValue: "model"))
            try container.encode(messages, forKey: DynamicCodingKey(stringValue: "messages"))
            try container.encode(stream, forKey: DynamicCodingKey(stringValue: "stream"))
            if let streamOptions {
                try container.encode(
                    streamOptions, forKey: DynamicCodingKey(stringValue: "stream_options")
                )
            }
            if let tools, !tools.isEmpty {
                try container.encode(tools, forKey: DynamicCodingKey(stringValue: "tools"))
            }
            try sampling.encode(into: &container)
        }
    }

    /// Body for `POST /v1/chat/completions`.
    /// `includeUsage` asks the server for real token counts in a final SSE
    /// chunk (`stream_options.include_usage`); servers that reject the field
    /// get retried by the provider without it — metrics then stay nil.
    ///
    /// `support` is the declared sampling surface of the server kind. A configured knob outside that
    /// schema is never written: LM Studio and any OpenAI-compatible server accept an unknown key and
    /// then ignore it, so sending `min_p` there would leave the user believing a knob is live.
    ///
    /// **The system prompt is not added here.** It arrives as the first entry of `request.messages`.
    public static func chatRequestBody(
        _ request: GenerationRequest,
        support: SamplingSupport,
        modelSupportsVision: Bool = false,
        includeUsage: Bool = true
    ) throws -> Data {
        var messages: [WireMessage] = []
        for payload in request.messages {
            let calls = payload.toolCalls.isEmpty
                ? nil : payload.toolCalls.map(WireToolCall.init)
            if modelSupportsVision && !payload.imageData.isEmpty {
                var parts: [WireContentPart] = []
                if !payload.text.isEmpty {
                    parts.append(WireContentPart(type: "text", text: payload.text, imageURL: nil))
                }
                for image in payload.imageData {
                    let url = "data:image/jpeg;base64,\(image.base64EncodedString())"
                    parts.append(
                        WireContentPart(type: "image_url", text: nil,
                                        imageURL: .init(url: url))
                    )
                }
                messages.append(
                    WireMessage(role: payload.role.rawValue, text: nil, parts: parts, images: nil,
                                toolCalls: calls, toolCallID: payload.toolCallID)
                )
            } else {
                messages.append(
                    WireMessage(role: payload.role.rawValue, text: payload.text, parts: nil,
                                images: nil, toolCalls: calls, toolCallID: payload.toolCallID)
                )
            }
        }
        let wire = WireRequest(
            model: request.modelID,
            messages: messages,
            stream: true,
            streamOptions: includeUsage ? .init(includeUsage: true) : nil,
            sampling: SamplingFieldList(
                sampling: request.config.sampling,
                support: support,
                dialect: .openAI
            ),
            // A prompt-protocol turn was told the call shapes in its system block instead; sending a
            // `tools` array to a server that was declared unable to use them is the claim this guard
            // exists to stop.
            tools: request.toolProtocol == .native && !request.tools.isEmpty
                ? WireToolSchema.schemas(request.tools) : nil
        )
        return try JSONEncoder().encode(wire)
    }
}
