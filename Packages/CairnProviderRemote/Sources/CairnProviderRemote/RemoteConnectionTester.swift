import Foundation
import CairnChatDomain

/// The profile editor's "Test" action.
///
/// Latency is measured on a monotonic clock; version and model count come only from
/// endpoints the dialect actually has; and every failure maps to the outcome case that
/// carries the teaching hint. No hostname is ever returned or logged.
@MainActor
public final class RemoteConnectionTester: RemoteTesting {
    private let transport: any RemoteTransport
    private let secrets: any SecretStoring

    public init(transport: any RemoteTransport = URLSessionTransport(), secrets: any SecretStoring) {
        self.transport = transport
        self.secrets = secrets
    }

    public func test(_ profile: ServerProfile) async -> RemoteTestOutcome {
        guard profile.usableNow else { return .optInRequired }
        guard !rejectsPlainHTTP(profile) else { return .rejectedPlainHTTP }

        let clock = ContinuousClock()
        let started = clock.now
        do {
            let wire = profile.kind.wire
            let data = try await exchange(profile, path: wire.modelsPath, accept: wire.listAccept)
            let latencyMs = Self.latencyMs(from: started, to: clock.now)
            let models = try wire.decodeModels(data, providerID: "remote:\(profile.id.uuidString)")
            // Ollama answers /api/version in one small round trip, so the version line in the
            // result is worth the extra request; other dialects have no version endpoint.
            let version = profile.kind == .ollama ? try await versionNumber(profile) : nil
            return .connected(version: version, modelCount: models.count, latencyMilliseconds: latencyMs)
        } catch {
            return outcome(for: RemoteError.classify(error))
        }
    }

    /// Plaintext may only reach loopback (also enforced when the profile is saved); anything
    /// else is refused here as defence in depth, since the app ships zero ATS exceptions.
    private func rejectsPlainHTTP(_ profile: ServerProfile) -> Bool {
        guard profile.isPlaintext else { return false }
        let host = URLComponents(string: profile.baseURLString)?.host?.lowercased() ?? ""
        return !ServerProfile.loopbackHosts.contains(host)
    }

    private func versionNumber(_ profile: ServerProfile) async throws -> String? {
        let data = try await exchange(profile, path: "/api/version", accept: "application/json")
        return OllamaCodec.decodeVersion(data)
    }

    private func exchange(_ profile: ServerProfile, path: String, accept: String) async throws -> Data {
        guard let request = RemoteRequests.make(
            profile: profile,
            method: "GET",
            path: path,
            accept: accept,
            bearer: secrets.secret(for: profile.id)
        ) else { throw RemoteError.invalidURL }
        return try await transport.exchange(request)
    }

    private static func latencyMs(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Int {
        max(1, Int((RemoteChatPipeline.elapsed(from: start, to: end) * 1_000).rounded()))
    }

    private func outcome(for error: RemoteError) -> RemoteTestOutcome {
        switch error {
        case .httpStatus(let status, _) where status == 401 || status == 403:
            return .unauthorized
        case .httpStatus(let status, _):
            return .httpStatus(status)
        case .hostNotFound:
            return .hostNotFound
        case .tlsFailure:
            return .tlsFailure
        case .connectionRefused:
            return .connectionRefused
        case .timedOut, .cancelled:
            return .timedOut
        case .plainHTTPBlocked:
            return .rejectedPlainHTTP
        case .optInRequired:
            return .optInRequired
        case .serverMessage, .malformedResponse, .transport, .invalidURL, .unsupportedOperation:
            return .malformedResponse
        }
    }
}
