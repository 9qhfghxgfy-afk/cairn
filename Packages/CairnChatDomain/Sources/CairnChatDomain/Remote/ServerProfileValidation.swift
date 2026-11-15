import Foundation

/// User-presentable validation failures for a server profile. Messages never echo
/// the full URL — the real MagicDNS hostname must not leak into a log, so this text
/// is UI-only.
public enum ServerProfileValidationError: Error, Equatable, LocalizedError, Sendable {
    case missingName
    case invalidURL
    case wrongScheme(String)
    case userInfoInURL
    case reservedHeader(String)
    case emptyHeaderName

    public var errorDescription: String? {
        switch self {
        case .missingName:
            return "Give the server a name."
        case .invalidURL:
            return "That is not a valid server URL."
        case .wrongScheme(let scheme):
            return "Only https:// is allowed (got \(scheme.isEmpty ? "no scheme" : scheme)). "
                + "Run `tailscale serve` on the server for HTTPS — the app ships zero ATS "
                + "exceptions, so plaintext http cannot connect (localhost excepted for development)."
        case .userInfoInURL:
            return "Remove the user info from the URL; tokens belong in the token field."
        case .reservedHeader(let name):
            return "\"\(name)\" is reserved: put the value in the token field instead — "
                + "tokens go to the Keychain, never to the settings store."
        case .emptyHeaderName:
            return "Custom header names cannot be empty."
        }
    }
}

extension ServerProfile {
    /// Full validation for the save path; throws user-presentable errors.
    public static func validate(name: String, urlString: String, headers: [String: String]) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerProfileValidationError.missingName
        }

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { throw ServerProfileValidationError.invalidURL }

        let host = components.host?.lowercased() ?? ""
        guard !host.isEmpty else { throw ServerProfileValidationError.invalidURL }
        if scheme == "http" && !loopbackHosts.contains(host) {
            throw ServerProfileValidationError.wrongScheme(scheme)
        }
        if components.user != nil || components.password != nil {
            throw ServerProfileValidationError.userInfoInURL
        }
        for (key, _) in headers {
            let headerName = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if headerName.isEmpty { throw ServerProfileValidationError.emptyHeaderName }
            // Credentials belong in the token field, which is Keychain-backed.
            if headerName.lowercased() == "authorization" {
                throw ServerProfileValidationError.reservedHeader(headerName)
            }
        }
    }
}
