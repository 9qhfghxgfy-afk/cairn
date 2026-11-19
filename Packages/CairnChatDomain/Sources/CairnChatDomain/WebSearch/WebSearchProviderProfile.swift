import Foundation

/// One configured search provider, as a value.
///
/// A profile is **non-secret by construction**: it holds `hasCredential`, the presence flag the row
/// shows, and never the token. That split is what lets the whole provider list live in the settings
/// store — and therefore be exported, diffed and read back — while the secret stays in the Keychain,
/// where a leak of the store cannot reach it.
///
/// The DuckDuckGo row is a real row rather than a special case in the UI, so "which provider is active"
/// is one question with one answer for every kind, and the built-in row cannot be deleted out from under
/// a user whose own instance has just broken.
public struct WebSearchProviderProfile: Sendable, Equatable, Codable, Identifiable {
    /// The id of the built-in row. Fixed on purpose: it is persisted, and a row that changes identity
    /// between launches cannot be the thing selection falls back to.
    public static let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000d0c") ?? UUID()

    public static let resultCountRange = 3...10
    public static let defaultResultCount = 5
    public static let timeoutRange = 5...60

    public let id: UUID
    public let kind: WebSearchProviderKind
    /// The id of the server profile a cloud row mirrors, so removing that profile or its key can remove
    /// this row. nil for every row the user added.
    public let sourceProfileID: UUID?

    public var displayName: String
    /// The address search is sent to. For DuckDuckGo this is the fixed endpoint, and for a cloud row the
    /// fixed cloud endpoint; only a SearXNG row is the user's to type.
    public var baseURLString: String
    public var categories: [String]
    public var language: String?
    public var safeSearch: WebSearchSafeSearch
    public var timeRange: WebSearchTimeRange?
    public var timeoutSeconds: Int
    /// How a stored secret would be sent, or nil when the provider needs none. The value is elsewhere.
    public var credentialShape: WebSearchCredentialShape?
    /// Presence only. This is the field the row renders; the token is never in a profile.
    public var hasCredential: Bool
    /// Ordinary, non-secret headers. Credential names are refused by validation, which is what keeps
    /// this list safe to persist.
    public var customHeaders: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: WebSearchProviderKind,
        sourceProfileID: UUID? = nil,
        displayName: String,
        baseURLString: String,
        categories: [String] = [],
        language: String? = nil,
        safeSearch: WebSearchSafeSearch = .default,
        timeRange: WebSearchTimeRange? = nil,
        timeoutSeconds: Int = WebSearchProviderProfile.defaultTimeoutSeconds,
        credentialShape: WebSearchCredentialShape? = nil,
        hasCredential: Bool = false,
        customHeaders: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.sourceProfileID = sourceProfileID
        self.displayName = displayName
        self.baseURLString = baseURLString
        self.categories = categories
        self.language = language
        self.safeSearch = safeSearch
        self.timeRange = timeRange
        self.timeoutSeconds = timeoutSeconds
        self.credentialShape = credentialShape
        self.hasCredential = hasCredential
        self.customHeaders = customHeaders
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static let defaultTimeoutSeconds = 15

    /// The row every install starts with, and the row selection falls back to.
    public static let builtIn = WebSearchProviderProfile(
        id: builtInID,
        kind: .duckDuckGo,
        displayName: "DuckDuckGo",
        baseURLString: WebSearchProviderKind.duckDuckGoEndpoint
    )

    public var isBuiltIn: Bool { kind.isBuiltIn }
    public var acceptsCredential: Bool { kind == .searxng }

    /// Where the request goes. nil means the stored address is unusable, which the row reports rather
    /// than sending a request to nothing.
    public var endpoint: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public var host: String {
        endpoint?.host?.lowercased() ?? ""
    }

    /// Where this provider's traffic goes, in the same three honest classes the server list uses. A
    /// fixed-endpoint kind is public by definition; a self-hosted row is classified from its own host.
    public var networkClass: NetworkClass {
        kind.fixedEndpoint != nil ? .publicInternet : NetworkClassRouting.classify(host: host)
    }

    /// True when a query to this provider crosses out of the user's own network, which is the condition
    /// the outbound badge and the consent sheet are both about.
    public var reachesPublicInternet: Bool { networkClass == .publicInternet }

    /// Plaintext to a public host is a validation failure, so a row that survives validation only shows
    /// this badge for a private address — which is the honest case for it.
    public var usesPlaintext: Bool {
        endpoint?.scheme?.lowercased() == "http"
    }

    /// The parameters this provider adds beyond the query, as one line for the row. Empty means the
    /// provider sends the query and nothing else.
    public var parameterSummary: String {
        var parts: [String] = []
        if !categories.isEmpty { parts.append(categories.joined(separator: ",")) }
        if let language, !language.isEmpty { parts.append("lang:\(language)") }
        if safeSearch != .default { parts.append("safe:\(safeSearch.label.lowercased())") }
        if let timeRange { parts.append("last \(timeRange.label.dropFirst(5).lowercased())") }
        return parts.joined(separator: " · ")
    }
}
