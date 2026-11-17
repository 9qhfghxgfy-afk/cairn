import Foundation
import CairnChatDomain

/// One configured remote server, exposed as a Cairn engine.
///
/// Stateless by design: the thinking toggle comes from `GenerationRequest.params` per turn
/// rather than being baked into the engine, so flipping it never invalidates an engine cache,
/// and the bearer token is read once at construction from the Keychain, never from disk.
public struct RemoteChatProvider: InferenceProvider {
    public let id: String
    public let displayName: String
    /// Kept public so the UI can render the network-class badge next to the engine.
    public let profile: ServerProfile

    private let wire: any RemoteWire
    private let transport: any RemoteTransport
    private let bearer: String?

    public init(profile: ServerProfile, bearer: String?, transport: any RemoteTransport) {
        // One owner for the engine-id string: the switcher and the session go from a profile to
        // this id and back, and a literal written here could drift from theirs.
        self.id = profile.engineID
        self.displayName = profile.name
        self.profile = profile
        self.wire = remoteWire(for: profile)
        self.transport = transport
        self.bearer = bearer
    }

    public var networkClass: NetworkClass { profile.networkClass }
    public var capabilities: ProviderCapabilities { wire.capabilities }
    /// The profile this engine was built from, so switching servers can restore that server's
    /// last model instead of guessing from a model name.
    public var serverProfileID: UUID? { profile.id }
    /// The dialect's documented fields, which is the same table `chatRequestBody` filters with —
    /// the sheet shows exactly what the encoder is willing to put on the wire.
    public var samplingSupport: SamplingSupport { profile.kind.samplingSupport }


    public func models() async throws -> [ModelInfo] {
        guard profile.usableNow else { throw RemoteError.optInRequired }
        let data = try await fetch(path: wire.modelsPath, accept: wire.listAccept)
        return try wire.decodeModels(data, providerID: id)
    }

    public func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
        let profile = self.profile
        let wire = self.wire
        let transport = self.transport
        let bearer = self.bearer

        return AsyncThrowingStream(StreamChunk.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    guard profile.usableNow else { throw RemoteError.optInRequired }
                    let body = try wire.chatBody(request)
                    guard let httpRequest = RemoteRequests.make(
                        profile: profile,
                        method: "POST",
                        path: wire.chatPath,
                        body: body,
                        accept: wire.chatAccept,
                        bearer: bearer
                    ) else { throw RemoteError.invalidURL }
                    try await RemoteChatPipeline.run(
                        httpRequest,
                        transport: transport,
                        wire: wire,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    // The pipeline already maps to a typed error (or to CancellationError when
                    // the user stopped the turn), so the session sees the honest outcome.
                    continuation.finish(throwing: error)
                }
            }
            // Terminating the stream (Stop, a dropped pane, or a cancelled turn) cancels the
            // URLSession task, which is what actually stops generation on the server side.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func fetch(path: String, accept: String) async throws -> Data {
        guard let request = RemoteRequests.make(
            profile: profile,
            method: "GET",
            path: path,
            accept: accept,
            bearer: bearer
        ) else { throw RemoteError.invalidURL }
        return try await transport.exchange(request)
    }
}
