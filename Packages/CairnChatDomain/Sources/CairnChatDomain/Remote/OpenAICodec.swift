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
        let temperature: Double
        let topP: Double
        let maxTokens: Int

        struct StreamOptions: Encodable { let includeUsage: Bool }

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, temperature
            case streamOptions = "stream_options"
            case topP = "top_p"
            case maxTokens = "max_tokens"
        }
    }

    /// Body for `POST /v1/chat/completions`.
    /// `includeUsage` asks the server for real token counts in a final SSE
    /// chunk (`stream_options.include_usage`); servers that reject the field
    /// get retried by the provider without it — metrics then stay nil.
    public static func chatRequestBody(
        _ request: GenerationRequest,
        modelSupportsVision: Bool = false,
        includeUsage: Bool = true
    ) throws -> Data {
        var messages: [WireMessage] = []
        let system = request.params.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            messages.append(WireMessage(role: "system", text: system, parts: nil, images: nil))
        }
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
            temperature: request.params.temperature,
            topP: request.params.topP,
            maxTokens: request.params.maxTokens
        )
        return try JSONEncoder().encode(wire)
    }
}
