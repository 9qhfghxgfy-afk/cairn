import Foundation

/// How a provider is authenticated, stated as a value — never the secret itself.
///
/// A search provider is usually behind something: a reverse proxy in front of a self-hosted instance
/// wants a bearer token or its own `X-API-Key`-style header, and which of the two it wants is the
/// operator's choice, not Cairn's. What is **not** a choice is where the value is kept: it lives in the
/// search Keychain service, and this enum only says how to use it once it is there. A named secret
/// header is validated against `HTTPHeaderNames` so the credential cannot be smuggled into an ordinary
/// header row, where it would be written to the settings store.
public enum WebSearchCredentialShape: Sendable, Equatable, Codable {
    /// `Authorization: Bearer <token>` — the reverse-proxy default.
    case bearer
    /// A single named header carrying the token, e.g. `X-API-Key`.
    case secretHeader(name: String)

    public static let `default` = WebSearchCredentialShape.bearer

    /// The header this shape fills, or nil for "no credential at all".
    public var headerName: String? {
        switch self {
        case .bearer: return "Authorization"
        case .secretHeader(let name): return name
        }
    }

    /// A name for the Settings row, so the user can see which shape a stored token is used as.
    public var label: String {
        switch self {
        case .bearer: return "Bearer token"
        case .secretHeader(let name): return "\(name) header"
        }
    }
}

/// What a user types to say "authenticate this provider", before it is validated.
///
/// Kept separate from `WebSearchCredentialShape` because the form has to be able to represent a mistake:
/// a half-typed header name or an empty token is a thing the editor has to show an error about, and a
/// validated shape cannot hold one.
public struct WebSearchCredentialDraft: Sendable, Equatable {
    public var shape: WebSearchCredentialShape
    /// The secret. Held only long enough to be written to the Keychain; a provider profile never keeps
    /// this field, only `hasCredential`.
    public var token: String

    public init(shape: WebSearchCredentialShape = .bearer, token: String = "") {
        self.shape = shape
        self.token = token
    }

    public var isEmpty: Bool { token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
