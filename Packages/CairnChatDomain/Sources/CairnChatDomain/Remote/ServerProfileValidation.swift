import Foundation

/// User-presentable validation failures for a server profile. Messages never echo
/// the full URL — the user's real hostname or address must not leak into a log, so
/// this text is UI-only.
public enum ServerProfileValidationError: Error, Equatable, LocalizedError, Sendable {
    case missingName
    case invalidURL
    case wrongScheme(String)
    case plaintextPublicInternet
    case userInfoInURL
    case reservedHeader(String)
    case emptyHeaderName
    /// A profile labelled Ollama Cloud whose address is not ollama.com.
    case cloudHostExpected

    public var errorDescription: String? {
        switch self {
        case .missingName:
            return "Give the server a name."
        case .invalidURL:
            return "That is not a valid server URL."
        case .wrongScheme(let scheme):
            return "A server URL must start with http:// or https:// (got "
                + "\(scheme.isEmpty ? "no scheme" : scheme)://)."
        case .plaintextPublicInternet:
            return "That host is on the public internet, so it needs https://. Plaintext "
                + "http is allowed only for a private address: a LAN address, an address "
                + "inside your VPN, a .local name, or a bare hostname."
        case .userInfoInURL:
            return "Remove the user info from the URL; tokens belong in the token field."
        case .reservedHeader(let name):
            return "\"\(name)\" is reserved: put the value in the token field instead — "
                + "tokens go to the Keychain, never to the settings store."
        case .emptyHeaderName:
            return "Custom header names cannot be empty."
        case .cloudHostExpected:
            return "Ollama Cloud is ollama.com. A server you run yourself is Ollama or "
                + "OpenAI-compatible — the label has to match where the traffic actually goes."
        }
    }
}

extension ServerProfile {
    /// Full validation for the save path; throws user-presentable errors.
    public static func validate(
        name: String,
        kind: ServerProfileKind,
        urlString: String,
        headers: [String: String]
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerProfileValidationError.missingName
        }

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              !scheme.isEmpty
        else { throw ServerProfileValidationError.invalidURL }
        // A foreign scheme gets its own message: "ftp://host" is a different mistake
        // from a private host over http, and the fix is different too.
        guard scheme == "https" || scheme == "http" else {
            throw ServerProfileValidationError.wrongScheme(scheme)
        }

        let host = components.host?.lowercased() ?? ""
        guard !host.isEmpty else { throw ServerProfileValidationError.invalidURL }
        if scheme == "http" && !NetworkClassRouting.classify(host: host).allowsPlaintext {
            throw ServerProfileValidationError.plaintextPublicInternet
        }
        if kind == .ollamaCloud && host != ServerBackend.cloudHost {
            throw ServerProfileValidationError.cloudHostExpected
        }
        if components.user != nil || components.password != nil {
            throw ServerProfileValidationError.userInfoInURL
        }
        for (key, _) in headers {
            let headerName = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if headerName.isEmpty { throw ServerProfileValidationError.emptyHeaderName }
            // Credentials belong in the token field, which is Keychain-backed. The list of names that can
            // only ever carry a credential is shared with search providers, so one rule covers both
            // settings surfaces — `Authorization` was the only one refused before, which left
            // `X-API-Key` and `Cookie` as a way to put a secret in the settings store by accident.
            if HTTPHeaderNames.isCredentialBearing(headerName) {
                throw ServerProfileValidationError.reservedHeader(headerName)
            }
        }
    }
}
