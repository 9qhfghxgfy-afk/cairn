import Foundation
import CairnChatDomain

/// Model management for remote servers.
///
/// The UI derives every button from `ProviderCapabilities`, so a dialect without an endpoint
/// should never be asked for it; if it is anyway, this fails with `unsupportedOperation`
/// rather than issuing a request that would 404 in a confusing way.
@MainActor
public final class RemoteModelService: RemoteModelManaging {
    private let transport: any RemoteTransport
    private let secrets: any SecretStoring

    public init(transport: any RemoteTransport = URLSessionTransport(), secrets: any SecretStoring) {
        self.transport = transport
        self.secrets = secrets
    }

    public func listModels(_ profile: ServerProfile) async throws -> [ModelInfo] {
        try await provider(for: profile).models()
    }

    public func loadedModels(_ profile: ServerProfile) async throws -> [String] {
        try requireOllama(profile)
        let data = try await exchange(profile, method: "GET", path: "/api/ps", body: nil, accept: "application/json")
        return try OllamaCodec.decodeModelList(data, providerID: providerID(for: profile)).map(\.id)
    }

    public func pull(model: String, profile: ServerProfile) async throws {
        try requireOllama(profile)
        // The pull response is an NDJSON progress stream: it must be drained to the end,
        // or the pull is abandoned halfway.
        try await drain(profile, path: "/api/pull", payload: ["name": model, "stream": true])
    }

    public func delete(model: String, profile: ServerProfile) async throws {
        try requireOllama(profile)
        _ = try await exchange(
            profile,
            method: "DELETE",
            path: "/api/delete",
            body: try json(["name": model]),
            accept: "application/json"
        )
    }

    private func provider(for profile: ServerProfile) -> RemoteChatProvider {
        RemoteChatProvider(profile: profile, bearer: secrets.secret(for: profile.id), transport: transport)
    }

    private func providerID(for profile: ServerProfile) -> String { "remote:\(profile.id.uuidString)" }

    private func requireOllama(_ profile: ServerProfile) throws {
        guard profile.kind == .ollama else { throw RemoteError.unsupportedOperation }
    }

    private func exchange(
        _ profile: ServerProfile,
        method: String,
        path: String,
        body: Data?,
        accept: String
    ) async throws -> Data {
        guard profile.usableNow else { throw RemoteError.optInRequired }
        guard let request = RemoteRequests.make(
            profile: profile,
            method: method,
            path: path,
            body: body,
            accept: accept,
            bearer: secrets.secret(for: profile.id)
        ) else { throw RemoteError.invalidURL }
        return try await transport.exchange(request)
    }

    /// Drains a progress stream, surfacing an in-band `{"error": ...}` line as a thrown
    /// error: Ollama reports pull failures with HTTP 200.
    private func drain(_ profile: ServerProfile, path: String, payload: [String: Any]) async throws {
        let data = try await exchange(profile, method: "POST", path: path, body: try json(payload), accept: "application/x-ndjson")
        var parser = LineStreamParser()
        var lines = parser.feed(data)
        if let tail = parser.takeTrailingPartialLine(), !tail.isEmpty { lines.append(tail) }
        let wire = profile.kind.wire
        for line in lines {
            for event in try wire.decodeLine(line) {
                if case .error(let message) = event { throw RemoteError.serverMessage(message) }
            }
        }
    }

    private func json(_ payload: [String: Any]) throws -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw RemoteError.malformedResponse
        }
        return data
    }
}
