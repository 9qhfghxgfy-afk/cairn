import Foundation
import CairnChatDomain

extension ServerProfileKind {
    /// The dialect that speaks to this kind of server. Adding a kind means adding a wire
    /// here and nowhere else: the provider, pipeline, tester, and model service all ask
    /// the profile for its wire.
    var wire: any RemoteWire {
        switch self {
        case .ollama: return OllamaWire()
        case .openAICompatible: return OpenAIWire()
        }
    }
}

/// Ollama's HTTP API (public, documented wire format): NDJSON chat stream, `/api/tags`
/// catalog, plus pull / delete / loaded-models, which no OpenAI-compatible server has.
struct OllamaWire: RemoteWire {
    var capabilities: ProviderCapabilities { .ollama }
    var chatPath: String { "/api/chat" }
    var modelsPath: String { "/api/tags" }
    var chatAccept: String { "application/x-ndjson" }
    var listAccept: String { "application/json" }

    /// `modelSupportsVision: true` because the capability is server-level in M2; the UI
    /// already gates image attachments to models badged `supportsVision` from the catalog.
    func chatBody(_ request: GenerationRequest) throws -> Data {
        try OllamaCodec.chatRequestBody(
            request,
            modelSupportsVision: true,
            thinking: request.params.thinkingEnabled
        )
    }

    func decodeLine(_ line: Data) throws -> [RemoteEvent] {
        try OllamaCodec.decodeNDJSONLine(line).flatMap { event in
            switch event {
            case .thinking(let text):
                return [.thinking(text)]
            case .content(let text):
                return [.content(text)]
            case .error(let message):
                return [.error(message)]
            case .finished(let info):
                var events: [RemoteEvent] = []
                if info.promptEvalCount != nil || info.evalCount != nil {
                    events.append(.usage(promptTokens: info.promptEvalCount, completionTokens: info.evalCount))
                }
                events.append(.finished(FinishReason(ollamaDoneReason: info.doneReason)))
                return events
            }
        }
    }

    func decodeModels(_ data: Data, providerID: String) throws -> [ModelInfo] {
        try OllamaCodec.decodeModelList(data, providerID: providerID)
    }
}

extension FinishReason {
    /// Ollama reports `done_reason` on the final line only. Older servers used "eot".
    init(ollamaDoneReason reason: String?) {
        switch reason {
        case "stop", "eot": self = .stop
        case "length": self = .length
        case "abort": self = .cancelled
        default: self = .unknown
        }
    }
}
