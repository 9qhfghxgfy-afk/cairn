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
        case usage(promptTokens: Int?, completionTokens: Int?)
        case finished(FinishReason)
        case streamDone
        case error(String)
    }

    // MARK: - Request encoding

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

        enum CodingKeys: String, CodingKey {
            case role, content
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            if let parts {
                try container.encode(parts, forKey: .content)
            } else {
                try container.encode(text ?? "", forKey: .content)
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
                messages.append(WireMessage(role: payload.role.rawValue, text: nil, parts: parts, images: nil))
            } else {
                messages.append(
                    WireMessage(role: payload.role.rawValue, text: payload.text, parts: nil, images: nil)
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
            )
        )
        return try JSONEncoder().encode(wire)
    }
}
