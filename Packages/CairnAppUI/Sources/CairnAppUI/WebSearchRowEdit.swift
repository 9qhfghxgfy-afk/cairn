import Foundation
import Observation
import CairnChatDomain

/// One provider row as the editor states it, before it is validated.
///
/// A value rather than a live profile because the editor has to be able to hold a mistake: a half-typed
/// address, an empty token, a credential-named header row. A validated `WebSearchProviderProfile` cannot
/// represent any of those, and an editor built on one would have to throw the mistake away before showing it.
///
/// `token` has three states on purpose. nil means "leave the stored secret exactly as it is" — which is what
/// an edit of a row's name means, and why the field starts empty rather than showing a stored token back. ""
/// means "remove it". Anything else means "this is the secret now". The value never enters the settings
/// store; it goes to the Keychain or nowhere.
public struct WebSearchRowEdit: Equatable, Sendable {
    /// nil for a row that does not exist yet.
    public var id: UUID?
    public var name: String
    public var address: String
    public var categories: [String]
    public var language: String
    public var timeoutSeconds: Int
    /// How a stored secret would travel, or nil for "this instance needs no credential".
    public var credentialShape: WebSearchCredentialShape?
    /// See the note above: nil leaves it, "" clears it, anything else replaces it.
    public var token: String?
    /// Ordinary header rows. A credential-named one is refused by validation, not stripped.
    public var customHeaders: [String: String]

    public init(
        id: UUID? = nil,
        name: String = "",
        address: String = "",
        categories: [String] = [],
        language: String = "",
        timeoutSeconds: Int = WebSearchProviderProfile.defaultTimeoutSeconds,
        credentialShape: WebSearchCredentialShape? = nil,
        token: String? = nil,
        customHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.categories = categories
        self.language = language
        self.timeoutSeconds = timeoutSeconds
        self.credentialShape = credentialShape
        self.token = token
        self.customHeaders = customHeaders
    }

    /// The editor's starting point for a saved row. The token is deliberately nil rather than read out of
    /// the Keychain: a settings screen that displays a stored secret is a settings screen that can screenshot
    /// one.
    public init(row: WebSearchProviderProfile) {
        self.init(
            id: row.id,
            name: row.displayName,
            address: row.baseURLString,
            categories: row.categories,
            language: row.language ?? "",
            timeoutSeconds: row.timeoutSeconds,
            credentialShape: row.credentialShape,
            token: nil,
            customHeaders: row.customHeaders
        )
    }
}
