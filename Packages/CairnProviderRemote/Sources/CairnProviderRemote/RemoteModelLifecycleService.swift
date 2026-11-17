import Foundation
import CairnChatDomain

/// The Model Manager's view of a server: what is loaded, what a model is, and moving models in
/// and out. A separate service from `RemoteModelService`, which stays as it was.
///
/// Every call is gated on the path this kind declares, so an OpenAI-compatible server never gets
/// a request to an endpoint it does not have. A public-internet profile is checked for the
/// outbound opt-in before the request is built, not after.
@MainActor
public final class RemoteModelLifecycleService: ModelLifecycleManaging {
    /// Internal rather than private: `+Pull.swift` extends this type from another file and owns
    /// the streaming half. Nothing outside this module can see them.
    let transport: any RemoteTransport
    let secrets: any SecretStoring

    public init(transport: any RemoteTransport = URLSessionTransport(), secrets: any SecretStoring) {
        self.transport = transport
        self.secrets = secrets
    }

    public func supportsLifecycle(_ profile: ServerProfile) -> Bool {
        let endpoints = profile.kind.backend.endpoints
        guard endpoints.lifecycleWired else { return false }
        return endpoints.running != nil || endpoints.show != nil
            || endpoints.load != nil || endpoints.unload != nil || endpoints.download != nil
    }

    public func guidance(_ profile: ServerProfile) -> String {
        supportsLifecycle(profile) ? "" : ModelLifecycleGuidance.text
    }

    public func runningModels(_ profile: ServerProfile) async throws -> [ResidentServerModel] {
        guard let path = profile.kind.backend.endpoints.running else {
            throw ModelLifecycleError.unsupported(profile.kind)
        }
        let data = try await exchange(profile, method: "GET", path: path, body: nil, accept: "application/json")
        switch profile.kind {
        case .ollama, .ollamaCloud:
            return OllamaLifecycleCodec.decodeRunning(data)
        case .lmStudio:
            let loaded = try LMStudioLifecycleCodec.decodeLoaded(data)
            return loaded.map { ResidentServerModel(id: $0, displayName: $0, serverName: $0) }
        case .openAICompatible:
            throw ModelLifecycleError.unsupported(profile.kind)
        }
    }

    public func detail(model: String, profile: ServerProfile) async throws -> ModelDetail {
        guard let path = profile.kind.backend.endpoints.show else {
            throw ModelLifecycleError.unsupported(profile.kind)
        }
        let data = try await exchange(
            profile,
            method: "POST",
            path: path,
            body: try OllamaLifecycleCodec.showRequestBody(model: model),
            accept: "application/json"
        )
        do {
            return try OllamaLifecycleCodec.decodeDetail(data, model: model)
        } catch {
            throw ModelLifecycleError.malformedResponse
        }
    }

    public func loadModel(model: String, profile: ServerProfile) async throws {
        // LM Studio is the only kind with a documented load route. Ollama loads a model when it is
        // first used and publishes no route to force it, so saying "unsupported" is the truth and
        // a POST to a guessed path would be a lie with a 404 attached.
        guard profile.kind == .lmStudio,
              let path = profile.kind.backend.endpoints.load else {
            throw ModelLifecycleError.unsupported(profile.kind)
        }
        let data = try await exchange(
            profile, method: "POST", path: path,
            body: try LMStudioLifecycleCodec.loadRequestBody(keys: [model]),
            accept: "application/json"
        )
        if case .refused(let message) = LMStudioLifecycleCodec.readAcceptance(data) {
            throw ModelLifecycleError.serverMessage(message)
        }
    }

    public func unload(model: String, profile: ServerProfile) async throws {
        switch profile.kind {
        case .ollama, .ollamaCloud:
            guard let path = profile.kind.backend.endpoints.unload else {
                throw ModelLifecycleError.unsupported(profile.kind)
            }
            // keep_alive 0 drains on the first event; the reply body is irrelevant, but it has to
            // be read to the end or the server keeps the model.
            _ = try await exchange(
                profile, method: "POST", path: path,
                body: try OllamaLifecycleCodec.unloadRequestBody(model: model),
                accept: "application/x-ndjson"
            )
        case .lmStudio:
            guard let path = profile.kind.backend.endpoints.unload else {
                throw ModelLifecycleError.unsupported(profile.kind)
            }
            let data = try await exchange(
                profile, method: "POST", path: path,
                body: try LMStudioLifecycleCodec.unloadRequestBody(keys: [model]),
                accept: "application/json"
            )
            if case .refused(let message) = LMStudioLifecycleCodec.readAcceptance(data) {
                throw ModelLifecycleError.serverMessage(message)
            }
        case .openAICompatible:
            throw ModelLifecycleError.unsupported(profile.kind)
        }
    }

    public func delete(model: String, profile: ServerProfile) async throws {
        // Only Ollama documents a delete route. LM Studio's library is its own to manage, and
        // inventing a route for it would delete nothing while reporting that it did.
        guard profile.kind == .ollama else {
            throw ModelLifecycleError.unsupported(profile.kind)
        }
        _ = try await exchange(
            profile, method: "DELETE", path: "/api/delete",
            body: try OllamaLifecycleCodec.deleteRequestBody(model: model),
            accept: "application/json"
        )
    }
}
