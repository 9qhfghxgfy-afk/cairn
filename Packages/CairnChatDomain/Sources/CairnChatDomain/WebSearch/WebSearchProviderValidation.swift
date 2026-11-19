import Foundation

/// The rules a provider row has to satisfy before it is stored or used.
///
/// The transport security rule is the important one, and it is the rule the server list already applies:
/// a host on the public internet must be reached over `https`, and a private address may use `http`,
/// because Apple's transport security gives no protection to an IP literal, a `.local` name or a bare
/// hostname — the network, not TLS, is what protects a LAN path. Plaintext to a public host is refused
/// rather than badged, because a search query is the user's own words.
public enum WebSearchProviderValidator {
    /// Parses and classifies one endpoint, throwing the specific reason it is unusable.
    public static func endpoint(_ raw: String, kind: WebSearchProviderKind) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), !scheme.isEmpty
        else { throw WebSearchProviderValidationError.invalidEndpoint }
        guard scheme == "https" || scheme == "http" else {
            throw WebSearchProviderValidationError.wrongScheme(scheme)
        }
        let host = components.host?.lowercased() ?? ""
        guard !host.isEmpty else { throw WebSearchProviderValidationError.invalidEndpoint }
        if components.user != nil || components.password != nil {
            throw WebSearchProviderValidationError.userInfoInEndpoint
        }
        // A fixed-endpoint kind is addressed by Cairn, not by the user: pointing "DuckDuckGo" at some
        // other host would make the row's name and its attribution a lie.
        if let fixed = kind.fixedEndpoint {
            guard trimmed.lowercased() == fixed.lowercased(), let url = URL(string: fixed) else {
                throw WebSearchProviderValidationError.fixedEndpointLocked(kind)
            }
            return url
        }
        if scheme == "http" && !NetworkClassRouting.classify(host: host).allowsPlaintext {
            throw WebSearchProviderValidationError.plaintextPublicInternet
        }
        guard let url = URL(string: trimmed) else {
            throw WebSearchProviderValidationError.invalidEndpoint
        }
        return url
    }

    /// Full validation for the save path.
    ///
    /// `isUserAdded` is what keeps the built-in row and a materialised cloud row out of the add path
    /// without special cases in the UI: only a SearXNG row may be created by a person.
    public static func validate(
        name: String,
        kind: WebSearchProviderKind,
        endpoint: String,
        categories: [String] = [],
        language: String? = nil,
        timeoutSeconds: Int,
        credentialShape: WebSearchCredentialShape? = nil,
        hasCredential: Bool = false,
        customHeaders: [String: String] = [:],
        isUserAdded: Bool = true
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebSearchProviderValidationError.missingName
        }
        if isUserAdded && !kind.isUserAddable {
            throw WebSearchProviderValidationError.notUserAddable(kind)
        }
        _ = try self.endpoint(endpoint, kind: kind)
        guard WebSearchProviderProfile.timeoutRange.contains(timeoutSeconds) else {
            throw WebSearchProviderValidationError.timeoutOutOfRange
        }
        if let language, !language.isEmpty, !isLanguageTag(language) {
            throw WebSearchProviderValidationError.languageInvalid
        }
        if categories.count > 8 || categories.contains(where: { !isCategoryName($0) }) {
            throw WebSearchProviderValidationError.categoryInvalid
        }
        if kind.requiresCredential && !hasCredential {
            throw WebSearchProviderValidationError.credentialRequired(kind)
        }
        if let shape = credentialShape {
            // A fixed-endpoint kind carries its own auth story; a hand-set credential on the built-in row
            // would be a token with nowhere honest to go.
            guard kind == .searxng else {
                throw WebSearchProviderValidationError.fixedEndpointLocked(kind)
            }
            if case .secretHeader(let headerName) = shape,
               !HTTPHeaderNames.isUsableSecretHeaderName(headerName) {
                throw WebSearchProviderValidationError.secretHeaderNameInvalid(headerName)
            }
        }
        try validateHeaderRows(customHeaders)
    }

    /// Ordinary header rows only. A credential-named header is refused here rather than stripped,
    /// because silently dropping a header the user can see on screen is a settings store that disagrees
    /// with the editor.
    static func validateHeaderRows(_ headers: [String: String]) throws {
        for (key, _) in headers {
            let headerName = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if headerName.isEmpty { throw WebSearchProviderValidationError.emptyHeaderName }
            if HTTPHeaderNames.isCredentialBearing(headerName) {
                throw WebSearchProviderValidationError.credentialInHeaderRow(headerName)
            }
        }
    }

    /// Clamps a requested result count into the range the settings control offers. Clamped rather than
    /// rejected: the number arrives from a stepper or from an older stored blob, and a rejected value
    /// would break a search the user can do nothing about.
    public static func normalizedResultCount(_ count: Int) -> Int {
        let bounds = WebSearchProviderProfile.resultCountRange
        return min(bounds.upperBound, max(bounds.lowerBound, count))
    }

    /// A language tag: two letters, optionally a region. Long enough for `zh-Hans-CN`, short enough that
    /// a sentence cannot be typed into the field.
    static func isLanguageTag(_ value: String) -> Bool {
        let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = tag.split(separator: "-")
        guard let head = pieces.first, head.count == 2, head.allSatisfy({ $0.isLetter }) else {
            return false
        }
        return pieces.dropFirst().allSatisfy { $0.count >= 2 && $0.count <= 8 }
    }

    static func isCategoryName(_ value: String) -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 32 else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

