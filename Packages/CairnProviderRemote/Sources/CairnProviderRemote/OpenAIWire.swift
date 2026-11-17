import Foundation
import CairnChatDomain

/// OpenAI-compatible chat-completions servers: SSE chat stream, `/v1/models` catalog.
/// `stream_options.include_usage` is requested because usage is the only source of measured
/// metrics, and it is off by default; the trailing usage-only chunk is what closes the stream.
struct OpenAIWire: RemoteWire {
    var kind: ServerProfileKind { .openAICompatible }
    var capabilities: ProviderCapabilities { .openAICompatible }
    var chatAccept: String { "text/event-stream" }
    var listAccept: String { "application/json" }

    /// `modelSupportsVision: false` in M2: the OpenAI-compatible catalog endpoint does not
    /// report vision support, so images are dropped rather than sent to a model that would
    /// reject them. Model-level vision support arrives with M3's on-device path.
    func chatBody(_ request: GenerationRequest) throws -> Data {
        try OpenAICodec.chatRequestBody(
            request,
            modelSupportsVision: capabilities.vision,
            includeUsage: true
        )
    }

    func decodeLine(_ line: Data) throws -> [RemoteEvent] {
        guard let text = String(data: line, encoding: .utf8) else { throw RemoteError.malformedResponse }
        // Blank lines separate SSE events, and comments/`event:` lines carry no payload.
        guard let payload = OpenAICodec.sseDataPayload(fromLine: text) else { return [] }
        return try OpenAICodec.decodeSSEPayload(payload).map { event in
            switch event {
            case .thinking(let text): return .thinking(text)
            case .content(let text): return .content(text)
            case .usage(let promptTokens, let completionTokens):
                return .usage(promptTokens: promptTokens, completionTokens: completionTokens)
            case .finished(let reason): return .finished(reason)
            case .streamDone: return .streamDone
            case .error(let message): return .error(message)
            }
        }
    }

    func decodeModels(_ data: Data, providerID: String) throws -> [ModelInfo] {
        try OpenAICodec.decodeModels(data, providerID: providerID)
    }
}
