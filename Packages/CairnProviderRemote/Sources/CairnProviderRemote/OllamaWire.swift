import Foundation
import CairnChatDomain

/// Ollama's HTTP API (public, documented wire format): NDJSON chat stream, `/api/tags`
/// catalog, plus pull / delete / loaded-models, which no OpenAI-compatible server has.
struct OllamaWire: RemoteWire {
    var kind: ServerProfileKind { .ollama }
    var capabilities: ProviderCapabilities { .ollama }
    var chatAccept: String { "application/x-ndjson" }
    var listAccept: String { "application/json" }

    /// `modelSupportsVision: true` because the capability is server-level in M2; the UI
    /// already gates image attachments to models badged `supportsVision` from the catalog.
    func chatBody(_ request: GenerationRequest) throws -> Data {
        try OllamaCodec.chatRequestBody(
            request,
            support: kind.samplingSupport,
            modelSupportsVision: true,
            thinking: request.config.thinkingEnabled
        )
    }

    func decodeLine(_ line: Data) throws -> [RemoteEvent] {
        // Built with an explicit accumulator rather than flatMap: the switch arms return
        // differently shaped arrays, and the overload set for flatMap cannot infer that.
        var events: [RemoteEvent] = []
        for event in try OllamaCodec.decodeNDJSONLine(line) {
            switch event {
            case .thinking(let text):
                events.append(.thinking(text))
            case .content(let text):
                events.append(.content(text))
            case .error(let message):
                events.append(.error(message))
            case .finished(let info):
                if info.promptEvalCount != nil || info.evalCount != nil {
                    events.append(
                        .usage(promptTokens: info.promptEvalCount, completionTokens: info.evalCount)
                    )
                }
                events.append(.finished(FinishReason(ollamaDoneReason: info.doneReason)))
            }
        }
        return events
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
