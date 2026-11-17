import Foundation
import CairnChatDomain

/// Ollama's hosted API at `https://ollama.com`.
///
/// The dialect is Ollama's own documented HTTP API — NDJSON chat, `/api/tags` catalog — so the
/// encoding is delegated to `OllamaWire` rather than forked. What differs is everything this
/// build can *claim*: the cloud refuses create/delete (Ollama's docs state that needs a local
/// server), so `ProviderCapabilities.ollamaCloud` declares neither, and thinking stays off
/// because no reasoning field has been observed from here — a reasoning panel appears only for a
/// backend proven to emit one.
///
/// **Real-network unverified.** Nothing in this file has been exercised against ollama.com from
/// this machine, and the app must not claim otherwise: listing or chatting here is an honest
/// error path until a run with a real key proves it. What is verified is that the profile can
/// only point at `ollama.com`, only over https, and only after the outbound opt-in.
struct OllamaCloudWire: RemoteWire {
    var kind: ServerProfileKind { .ollamaCloud }
    var capabilities: ProviderCapabilities { .ollamaCloud }
    var chatAccept: String { "application/x-ndjson" }
    var listAccept: String { "application/json" }

    private let localDialect = OllamaWire()

    func chatBody(_ request: GenerationRequest) throws -> Data {
        // `thinking: false` is deliberate and independent of the request toggle: the cloud's
        // reasoning behaviour is unverified, and the rule is never to ask a backend for reasoning
        // it has not been seen to produce.
        try OllamaCodec.chatRequestBody(
            request,
            support: kind.samplingSupport,
            modelSupportsVision: false,
            thinking: false
        )
    }

    func decodeLine(_ line: Data) throws -> [RemoteEvent] {
        try localDialect.decodeLine(line)
    }

    func decodeModels(_ data: Data, providerID: String) throws -> [ModelInfo] {
        try OllamaCodec.decodeModelList(data, providerID: providerID)
    }
}
