import Foundation
import CairnChatDomain

/// Normalized streaming vocabulary. Both wire dialects map their own events into this,
/// so the pipeline that turns events into `StreamChunk`s exists once.
enum RemoteEvent: Sendable, Equatable {
    case thinking(String)
    case content(String)
    case usage(promptTokens: Int?, completionTokens: Int?)
    case finished(FinishReason)
    case streamDone
    case error(String)
}

/// One server dialect: what it can do, which kind it belongs to, its chat body, and how one
/// line of its stream becomes events. Framing is not part of this contract — `LineStreamParser`
/// already delivers complete lines for both NDJSON and SSE.
///
/// Paths are **not** part of a wire. They come from `ServerBackend`, the single pure-data map of
/// kind → endpoints, so a dialect can never invent a path and two places cannot disagree about
/// one. A wire only decides how to talk once it knows where to knock.
protocol RemoteWire: Sendable {
    var kind: ServerProfileKind { get }
    var capabilities: ProviderCapabilities { get }
    var chatAccept: String { get }
    var listAccept: String { get }

    func chatBody(_ request: GenerationRequest) throws -> Data
    func decodeLine(_ line: Data) throws -> [RemoteEvent]
    func decodeModels(_ data: Data, providerID: String) throws -> [ModelInfo]
}

extension RemoteWire {
    var chatPath: String { kind.backend.endpoints.chat }
    var modelsPath: String { kind.backend.endpoints.models }
}

/// The dialect that speaks to a saved profile. Adding a kind means adding a case here, its
/// entry in `ServerBackend`, and a wire — nowhere else.
func remoteWire(for profile: ServerProfile) -> any RemoteWire {
    switch profile.kind {
    case .ollama: return OllamaWire()
    case .ollamaCloud: return OllamaCloudWire()
    case .lmStudio: return LMStudioWire()
    case .openAICompatible: return OpenAIWire()
    }
}
