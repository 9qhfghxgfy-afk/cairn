import Foundation

/// Typed, user-presentable transport failures.
///
/// These never carry a URL, a hostname, a token, or a response body: an error string
/// can end up in an alert, a crash report, or a CI log, and the real MagicDNS hostname
/// must not travel any of those paths. Only status codes and server-supplied
/// operational messages (which the user's own server writes) are carried.
public enum RemoteError: Error, Equatable, Sendable, LocalizedError {
    case invalidURL
    case httpStatus(Int, serverMessage: String?)
    case serverMessage(String)
    case malformedResponse
    case optInRequired
    case unsupportedOperation
    case cancelled
    case timedOut
    case hostNotFound
    case tlsFailure
    case connectionRefused
    case plainHTTPBlocked
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That server URL cannot be used. Check the base URL in the profile."
        case .httpStatus(let status, let message):
            if let message, !message.isEmpty { return "Server returned HTTP \(status): \(message)" }
            return "Server returned HTTP \(status)."
        case .serverMessage(let message):
            return "Server reported: \(message)"
        case .malformedResponse:
            return "The server sent something that could not be parsed."
        case .optInRequired:
            return "This server is on the public internet. Turn on the outbound opt-in first."
        case .unsupportedOperation:
            return "This server does not support that action."
        case .cancelled:
            return "The request was cancelled."
        case .timedOut:
            return "The server did not answer in time. Is it running, and is Tailscale connected?"
        case .hostNotFound:
            return "Hostname not found. Check the Tailscale connection on this iPhone and that MagicDNS is on."
        case .tlsFailure:
            return "TLS failed. tailscale serve renews its certificate automatically, so re-check the https URL."
        case .connectionRefused:
            return "Connection refused. Run tailscale serve --bg --https=443 <port> on the server."
        case .plainHTTPBlocked:
            return "Plaintext http is blocked: this app ships zero ATS exceptions. Use tailscale serve HTTPS."
        case .transport(let reason):
            return "Connection problem: \(reason)"
        }
    }
}
