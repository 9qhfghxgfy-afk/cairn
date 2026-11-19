import Foundation

/// Header names that can only ever carry a credential.
///
/// A custom header row is an ordinary settings value: it is written to the settings store, it is shown
/// in an editor, and its text is copied into every request that goes out. A credential sitting in one of
/// those rows is a credential in the settings store, which is exactly what the token field exists to
/// avoid. So these names are refused in **every** custom header list — server profiles and search
/// providers both — and the value belongs in the field that is Keychain-backed.
///
/// Matching ignores case and inner whitespace, so a spelling trick cannot smuggle the same header past
/// the check.
public enum HTTPHeaderNames {
    /// Names whose value is a credential by definition.
    public static let credentialBearing: Set<String> = [
        "authorization", "proxy-authorization", "x-api-key", "api-key", "cookie", "set-cookie",
        "x-auth-token", "x-access-token",
    ]

    /// The comparison form: lowercase, no whitespace anywhere in the name.
    public static func normalized(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace }
    }

    /// True when a header with this name could only ever hold a secret. An empty name is the
    /// empty-name rule's business, not this one.
    public static func isCredentialBearing(_ name: String) -> Bool {
        credentialBearing.contains(normalized(name))
    }

    /// A header name a provider's own credential may legitimately be sent under — a named secret
    /// header, which is what a reverse proxy in front of a search instance usually wants.
    public static func isUsableSecretHeaderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 64 else { return false }
        // Token characters only: a header name may not contain a space, a colon, or a control.
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
