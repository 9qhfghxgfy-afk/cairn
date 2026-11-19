import Foundation

/// The two app-wide switches a web tool reads, stored as one value.
///
/// `outboundAllowed` is the acknowledgement the composer's `Tools` chip asks for the first time a chat
/// is armed for a tool that could reach the public internet: from then on Cairn may send a search query
/// out, and shows the outbound badge while it does. `searxngURL` is a non-secret endpoint the user runs
/// themselves; typing it is the strongest privacy choice available, because a self-hosted search server
/// removes the third party from the request entirely.
public struct WebToolSettings: Sendable, Equatable, Codable {
    public var outboundAllowed: Bool
    /// **Legacy.** The single SearXNG address from before providers existed. Read once by
    /// `WebSearchMigration` so an upgrade imports an address instead of losing it; the active provider row
    /// is what decides where a query goes now.
    public var searxngURL: String?
    /// Whether a page may be read off this device, as one answer for the whole tool: nil means the question
    /// has never been put, true means it was allowed, false means it was refused and is remembered.
    ///
    /// It is a single bit rather than one record per host because the destinations are unbounded — a tool
    /// that asked afresh about every host would be asking all day, and a person who has answered "yes" to
    /// reading pages has already answered the question that matters. Search keeps its per-provider record
    /// because there the subject is a specific third party the user chose, and a grant given to one instance
    /// must not travel to another.
    ///
    /// Held optional for the same reason the whole struct is optional: a synthesized decoder reads a missing
    /// key as nil, so an upgrade from a build without this field still decodes.
    public var fetchAllowed: Bool?
    /// The provider list, the active row, the result count and per-provider consent. nil means "this build's
    /// settings predate providers", which reads as `WebSearchSettings.default` — DuckDuckGo active, five
    /// results, nothing consented to. Held **optional** for the same reason the whole struct is: a
    /// synthesized decoder reads a missing optional key as nil, while a missing required key would fail the
    /// row and drop the user's theme with it.
    public var search: WebSearchSettings?

    public init(
        outboundAllowed: Bool = false,
        searxngURL: String? = nil,
        fetchAllowed: Bool? = nil,
        search: WebSearchSettings? = nil
    ) {
        self.outboundAllowed = outboundAllowed
        self.searxngURL = searxngURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fetchAllowed = fetchAllowed
        self.search = search
    }

    public static let `default` = WebToolSettings()
}

public extension AppSettings {
    /// No stored row means the shipped posture: nothing may leave the device through a tool.
    var outboundWebAllowed: Bool { webTools?.outboundAllowed ?? false }

    var searxngURL: String? { webTools?.searxngURL }

    /// The page-reading answer as one record: nil means the question has never been put, so the tool has to
    /// ask rather than assume. Absent is not permission.
    var webFetchAllowed: Bool? { webTools?.fetchAllowed }

    mutating func setWebFetchAllowed(_ allowed: Bool?) {
        var updated = webTools ?? .default
        updated.fetchAllowed = allowed
        webTools = updated
    }

    mutating func setOutboundWebAllowed(_ allowed: Bool) {
        var updated = webTools ?? .default
        updated.outboundAllowed = allowed
        webTools = updated
    }

    /// The user's own SearXNG endpoint; nil or empty means "not set".
    ///
    /// **Legacy.** This no longer routes anything — the active provider row does — but the field and its
    /// writer stay until the import has run on every install, because deleting the row would take away the
    /// only record a pre-provider user has of their own instance.
    mutating func setSearXNGURL(_ url: String?) {
        var updated = webTools ?? .default
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.searxngURL = (trimmed?.isEmpty == false) ? trimmed : nil
        webTools = updated
    }
}
