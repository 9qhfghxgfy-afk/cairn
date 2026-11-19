import Foundation

/// The one-shot upgrade from the old single SearXNG address to a provider row.
///
/// Before providers existed, Settings held one text field: your SearXNG address, and if it was set then it
/// won. Deleting that field without importing it would mean a person who already did the work of running an
/// instance — the hardest part of the whole feature — silently loses it on the next launch and quietly goes
/// back to sending queries to a third party. That is the worst possible outcome of an upgrade, so the
/// address becomes a named row **and stays the active one**.
///
/// The import is idempotent and it does not invent anything: an address that fails validation is left
/// exactly where it was, and the caller keeps the legacy field until the import succeeds.
public enum WebSearchMigration {
    /// Imports one legacy address. Returns true only when a row was actually added, which is what lets the
    /// caller clear the legacy field on success and leave it alone otherwise.
    @discardableResult
    public static func importLegacySearxngURL(
        _ raw: String?,
        into settings: inout WebSearchSettings,
        now: Date = Date()
    ) -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return false }
        // Same address already in the list means this already happened. Comparing the parsed endpoint
        // rather than the string means a trailing slash cannot cause a duplicate row.
        if settings.allProviders.contains(where: { row in
            row.kind == .searxng && Self.comparable(row.baseURLString) == Self.comparable(trimmed)
        }) { return false }

        var search = settings
        let host = URLComponents(string: trimmed)?.host?.lowercased() ?? ""
        var profile = WebSearchProviderProfile(
            kind: .searxng,
            displayName: suggestedName(forHost: host),
            baseURLString: trimmed
        )
        profile.updatedAt = now
        profile.createdAt = now
        guard (try? search.providers.add(profile, now: now)) != nil else { return false }
        settings = search
        return true
    }

    /// A name from the address, because a row called "SearXNG" is only useful to someone with one
    /// instance.
    ///
    /// An IP-literal host gets a generic label instead: the address is already shown in the row's
    /// sub-label, and a name that repeats it makes every screenshot of this screen carry the user's
    /// network layout.
    public static func suggestedName(forHost host: String) -> String {
        let cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return "SearXNG" }
        if cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) { return "SearXNG (LAN)" }
        let labels = cleaned.split(separator: ".").filter { !$0.isEmpty }
        guard let first = labels.first else { return "SearXNG" }
        let head = (first == "www" && labels.count > 1) ? labels[1] : first
        let name = head.prefix(24)
        return name.isEmpty ? "SearXNG" : "SearXNG — \(name)"
    }

    /// The address with its scheme lowercased and its trailing slash removed, for equality only.
    static func comparable(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
    }
}
