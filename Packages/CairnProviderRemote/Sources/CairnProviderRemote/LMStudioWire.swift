import Foundation
import CairnChatDomain

/// LM Studio's server: its own REST surface for the model list, and the OpenAI-compatible
/// endpoint it serves on the same port for the chat stream.
///
/// The split is LM Studio's, not ours — it publishes `/v1/chat/completions` alongside its native
/// `/api/v1/...` routes, so the chat uses the documented OpenAI dialect (SSE, usage in the final
/// chunk) while the catalog comes from the native list, which knows things the OpenAI view does
/// not: whether a model is resident, and what its key is.
///
/// Lifecycle routes (`load` / `unload` / `download`) are declared in `ServerBackend` but not
/// issued here: their request bodies are not something this machine can verify, so they stay
/// unwired behind `endpoints.lifecycleWired == false` until M3 proves them against a real
/// server. A declared endpoint is not a working one.
struct LMStudioWire: RemoteWire {
    var kind: ServerProfileKind { .lmStudio }
    var capabilities: ProviderCapabilities { .lmStudio }
    var chatAccept: String { "text/event-stream" }
    var listAccept: String { "application/json" }

    /// Chat is delegated rather than duplicated: one OpenAI-compatible body and one SSE decoder,
    /// used by both kinds.
    private let chatDialect = OpenAIWire()

    func chatBody(_ request: GenerationRequest) throws -> Data {
        try chatDialect.chatBody(request)
    }

    func decodeLine(_ line: Data) throws -> [RemoteEvent] {
        try chatDialect.decodeLine(line)
    }

    func decodeModels(_ data: Data, providerID: String) throws -> [ModelInfo] {
        try LMStudioCodec.decodeModels(data, providerID: providerID)
    }
}
