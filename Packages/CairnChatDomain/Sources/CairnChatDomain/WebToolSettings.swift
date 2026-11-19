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
    /// The provider list, the active row, the result count and per-provider consent. nil means "this build's
    /// settings predate providers", which reads as `WebSearchSettings.default` — DuckDuckGo active, five
    /// results, nothing consented to. Held **optional** for the same reason the whole struct is: a
    /// synthesized decoder reads a missing optional key as nil, while a missing required key would fail the
    /// row and drop the user's theme with it.
    public var search: WebSearchSettings?

    public init(
        outboundAllowed: Bool = false,
        searxngURL: String? = nil,
        search: WebSearchSettings? = nil
    ) {
        self.outboundAllowed = outboundAllowed
        self.searxngURL = searxngURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.search = search
    }

    public static let `default` = WebToolSettings()

    /// The routing this build's settings describe, before the active server is taken into account.
    /// The Keychain is not read here — the app layer says whether the active cloud profile has a key,
    /// because a settings value must never be the thing that reaches for a secret.
    public func routing(hasOllamaCloudKey: Bool = false) -> WebSearchRouting {
        WebSearchRouting(searxngURL: searxngURL, hasOllamaCloudKey: hasOllamaCloudKey)
    }
}

public extension AppSettings {
    /// No stored row means the shipped posture: nothing may leave the device through a tool.
    var outboundWebAllowed: Bool { webTools?.outboundAllowed ?? false }

    var searxngURL: String? { webTools?.searxngURL }

    func routing(hasOllamaCloudKey: Bool = false) -> WebSearchRouting {
        (webTools ?? .default).routing(hasOllamaCloudKey: hasOllamaCloudKey)
    }

    mutating func setOutboundWebAllowed(_ allowed: Bool) {
        var updated = webTools ?? .default
        updated.outboundAllowed = allowed
        webTools = updated
    }

    /// Empty means "not set" rather than "set to nothing", which is what makes the keyless default the
    /// answer instead of a broken endpoint.
    mutating func setSearXNGURL(_ url: String?) {
        var updated = webTools ?? .default
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.searxngURL = (trimmed?.isEmpty == false) ? trimmed : nil
        webTools = updated
    }
}
