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

/// One server dialect: its endpoints, its chat body, and how one line of its stream
/// becomes events. Framing is not part of this contract — `LineStreamParser` already
/// delivers complete lines for both NDJSON and SSE.
protocol RemoteWire: Sendable {
    var capabilities: ProviderCapabilities { get }
    var chatPath: String { get }
    var modelsPath: String { get }
    var chatAccept: String { get }
    var listAccept: String { get }

    func chatBody(_ request: GenerationRequest) throws -> Data
    func decodeLine(_ line: Data) throws -> [RemoteEvent]
    func decodeModels(_ data: Data, providerID: String) throws -> [ModelInfo]
}

func remoteWire(for profile: ServerProfile) -> any RemoteWire {
    profile.kind.wire
}
