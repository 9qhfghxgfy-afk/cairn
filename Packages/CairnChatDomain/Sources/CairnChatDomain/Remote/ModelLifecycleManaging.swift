import Foundation

/// Why a lifecycle action cannot be offered for a given server.
public enum ModelLifecycleError: Error, Equatable {
    /// This dialect has no such operation, so no request is sent and no 404 is possible.
    case unsupported(ServerProfileKind)
    /// A public-internet profile with no outbound opt-in. Checked before the request, not after.
    case optInRequired
    /// The server answered, but not in a shape this code can read.
    case malformedResponse
    /// The server said no, in its own words.
    case serverMessage(String)
    /// A stored profile whose address cannot be turned into a request. Reported, never retried.
    case invalidURL

    public var message: String {
        switch self {
        case .unsupported(let kind):
            return "\(kind.displayName) does not offer that model operation."
        case .optInRequired:
            return "This server is on the public internet. Turn on network access first."
        case .malformedResponse:
            return "The server replied in a form Cairn could not read."
        case .serverMessage(let text):
            return text
        case .invalidURL:
            return "That server address cannot be used. Check it in the Servers screen."
        }
    }
}

/// Model lifecycle: what is loaded, what a model really is, and moving models in and out.
///
/// This is a SEPARATE boundary from `RemoteModelManaging`, which stays exactly as it was so every
/// existing conformance and test keeps working. The difference is real, not cosmetic: the old
/// boundary drains a pull to completion and returns nothing, while this one streams progress and
/// hands back a way to cancel it — and it adds the loaded-model and detail reads the Model Manager
/// needs.
///
/// Every method is gated on the declared backend, so a dialect with no such endpoint fails here
/// rather than firing a request that 404s in a confusing way.
@MainActor
public protocol ModelLifecycleManaging: AnyObject {
    /// True when this server can answer the lifecycle calls at all. The Model Manager builds its
    /// buttons from this, not from a guess about the kind's name.
    func supportsLifecycle(_ profile: ServerProfile) -> Bool

    /// What to tell the user when lifecycle is not available for this server. Copy, not a
    /// disabled control with no explanation.
    func guidance(_ profile: ServerProfile) -> String

    /// Models the server reports as loaded in its own memory now, with the sizes it reported.
    func runningModels(_ profile: ServerProfile) async throws -> [ResidentServerModel]

    /// Published metadata for one model. Absent fields stay absent; nothing is inferred.
    func detail(model: String, profile: ServerProfile) async throws -> ModelDetail

    /// A model download, streamed. Cancelled by cancelling the consuming task or by ending the
    /// iteration early — the producer must close, not just stop being read.
    func pull(model: String, profile: ServerProfile) -> AsyncThrowingStream<ModelPullProgress, any Error>

    /// Ask the server to put a model into memory. Ollama loads on demand and publishes no such
    /// route, so it reports `unsupported` rather than firing a request that would do nothing.
    func loadModel(model: String, profile: ServerProfile) async throws

    /// Release a loaded model from the server's memory. The model stays installed.
    func unload(model: String, profile: ServerProfile) async throws

    /// Remove an installed model from the server's storage.
    func delete(model: String, profile: ServerProfile) async throws
}

/// The copy shown when a server has no lifecycle surface. An enum rather than a protocol
/// extension, because a stored static is not allowed in one — and because this is a piece of
/// wording, not behaviour.
public enum ModelLifecycleGuidance {
    /// Naming the three places lifecycle does work beats a greyed-out button with no reason.
    public static let text =
        "This server only lists models and answers. Loading, unloading, and downloading apply to Ollama, LM Studio, and On-Device models."
}
