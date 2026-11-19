import Foundation

/// Why a search provider row cannot be saved or used, in words a user can act on.
///
/// The messages name the field, never the value: a real hostname is the user's own infrastructure and
/// must not end up in a log or a crash report, so this text says what is wrong with an address without
/// repeating it.
public enum WebSearchProviderValidationError: Error, Equatable, LocalizedError, Sendable {
    case missingName
    case invalidEndpoint
    case wrongScheme(String)
    case plaintextPublicInternet
    case userInfoInEndpoint
    case fixedEndpointLocked(WebSearchProviderKind)
    /// The built-in row cannot be deleted.
    case builtInIsPermanent
    case notUserAddable(WebSearchProviderKind)
    case credentialRequired(WebSearchProviderKind)
    case secretHeaderNameInvalid(String)
    case credentialInHeaderRow(String)
    case emptyHeaderName
    case timeoutOutOfRange
    case languageInvalid
    case categoryInvalid

    public var errorDescription: String? {
        switch self {
        case .missingName:
            return "Give the provider a name you will recognise in the list."
        case .invalidEndpoint:
            return "That is not a valid search address. Include the scheme, like https:// or http://."
        case .wrongScheme(let scheme):
            return "A search address must start with https:// or http:// (got "
                + "\(scheme.isEmpty ? "no scheme" : scheme)://)."
        case .plaintextPublicInternet:
            return "That host is on the public internet, so it needs https://. Plain http is allowed "
                + "only for a private address: a LAN address, an address inside your own tunnel, a "
                + ".local name, or a bare hostname."
        case .userInfoInEndpoint:
            return "Take the user info out of the address. A token belongs in the credential field, "
                + "which is stored in the Keychain."
        case .fixedEndpointLocked(let kind):
            return "\(kind.displayName) has a fixed address, so the address cannot be edited here."
        case .builtInIsPermanent:
            return "DuckDuckGo stays in the list. There has to be a provider left that works when your "
                + "own instance does not."
        case .notUserAddable(let kind):
            return "\(kind.displayName) is not added by hand. \(kind.setupHint)"
        case .credentialRequired(let kind):
            return "\(kind.displayName) needs a credential — without one there is nothing to "
                + "search with."
        case .secretHeaderNameInvalid(let name):
            return "\"\(name)\" is not a usable header name. Use letters, numbers, - or _, with no "
                + "spaces."
        case .credentialInHeaderRow(let name):
            return "\"\(name)\" can only carry a credential. Put the value in the credential field "
                + "instead — it goes to the Keychain, never to the settings store."
        case .emptyHeaderName:
            return "Header names cannot be empty."
        case .timeoutOutOfRange:
            return "The timeout must be between \(WebSearchProviderProfile.timeoutRange.lowerBound) "
                + "and \(WebSearchProviderProfile.timeoutRange.upperBound) seconds."
        case .languageInvalid:
            return "Use a short language tag, like en or en-US."
        case .categoryInvalid:
            return "Categories are short names such as general, news or it, separated by commas."
        }
    }
}
