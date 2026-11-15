import Foundation

/// Typed, user-presentable result of "Test connection" in the server editor.
/// Hints teach the fix instead of dumping socket trivia, and none of the text
/// may echo the user's real hostname into a log.
public enum RemoteTestOutcome: Sendable, Equatable {
    case connected(version: String?, modelCount: Int, latencyMilliseconds: Int)
    case optInRequired
    case rejectedPlainHTTP
    case hostNotFound
    case tlsFailure
    case connectionRefused
    case timedOut
    case unauthorized
    case httpStatus(Int)
    case malformedResponse

    public var isSuccess: Bool {
        if case .connected = self { return true }
        return false
    }

    public var userMessage: String {
        switch self {
        case .connected(let version, let modelCount, let latency):
            let v = version.map { " (server \($0))" } ?? ""
            return "Connected in \(latency) ms — \(modelCount) model\(modelCount == 1 ? "" : "s")\(v)."
        case .optInRequired:
            return "This server is on the public internet. Tick the outbound opt-in first."
        case .rejectedPlainHTTP:
            return "Plaintext http is blocked (zero ATS exceptions). Use tailscale serve HTTPS."
        case .hostNotFound:
            return "Hostname not found. Is the Tailscale app connected on this iPhone, "
                + "and is MagicDNS on? tailscale serve gives the right https:// name."
        case .tlsFailure:
            return "TLS failed. Re-check the https URL; tailscale serve renews its "
                + "Let's Encrypt certificate automatically."
        case .connectionRefused:
            return "Connection refused. Is the server running and is the port forwarded "
                + "with tailscale serve --bg --https=443 <port>?"
        case .timedOut:
            return "Timed out. The server or Tailscale may be unreachable right now."
        case .unauthorized:
            return "The server rejected the token (401). Check the token field."
        case .httpStatus(let status):
            return "Server answered with HTTP \(status)."
        case .malformedResponse:
            return "The server response could not be parsed."
        }
    }
}

/// Boundary so the UI can call a tester without importing any networking
/// module; `CairnProviderRemote` implements it.
@MainActor
public protocol RemoteTesting: AnyObject {
    func test(_ profile: ServerProfile) async -> RemoteTestOutcome
}

/// CRUD boundary for server profiles; implemented in `CairnPersistence`.
/// Values must already be validated — the store never re-invents rules.
@MainActor
public protocol ServerProfileStoring: AnyObject {
    func profiles() throws -> [ServerProfile]
    func save(_ profile: ServerProfile) throws
    func delete(id: UUID) throws
}

/// Small secret store boundary (Keychain in `CairnProviderRemote`).
/// Values go in per profile id; nothing here is ever logged.
@MainActor
public protocol SecretStoring: AnyObject {
    func setSecret(_ secret: String, for id: UUID) throws
    func secret(for id: UUID) -> String?
    func removeSecret(for id: UUID) throws
}