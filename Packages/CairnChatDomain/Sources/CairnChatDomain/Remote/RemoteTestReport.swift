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
            return "Plaintext http is allowed only for a private address. This host is on "
                + "the public internet, so use https://."
        case .hostNotFound:
            return "Host not found. Check the address and the port — and if you are away from "
                + "home, that the VPN tunnel to your network is connected."
        case .tlsFailure:
            return "TLS failed. Re-check the https URL and the server's certificate; a plain "
                + "LAN server should be addressed with http:// instead."
        case .connectionRefused:
            return "Connection refused. Nothing is listening at that address and port: is the "
                + "server running, is the port right, and is it bound to the LAN rather than "
                + "only to 127.0.0.1? The first connection from this iPhone also needs the "
                + "Local Network permission."
        case .timedOut:
            return "Timed out. The server may be asleep, or the route to it may be missing — "
                + "away from home that usually means the VPN is not connected."
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