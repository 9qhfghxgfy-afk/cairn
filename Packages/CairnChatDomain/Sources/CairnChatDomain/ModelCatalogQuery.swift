import Foundation

/// Narrowing the Download list by several capabilities at once, and offering what the curated list
/// does not carry.
///
/// Pure, so a filter can be proved with no simulator and no network. Two rules are the reason this
/// file exists:
///
/// * **Chips narrow, they never widen.** A `Vision` chip that also kept the text-only models would
///   promise a capability the phone then fails to use, and the person finds out mid-turn.
/// * **A typed name that is not curated is still installable.** Cairn's list is short; the
///   repositories and the Ollama library are not. Answering "nothing here" to an exact name reads as
///   a broken search rather than as a name Cairn has not curated.
///
/// The search rule itself is `LocalCatalogQuery.matches`, shared rather than copied: the same words
/// must not mean two different things depending on which path a screen took to filter.
public enum ModelCatalogQuery {
    /// Longest name accepted for a typed name, so a pasted paragraph is not offered as a model.
    static let maximumNameLength = 120

    /// The rows the filter leaves, in the order the filter asks for, with the typed name appended as
    /// its own card when the library does not carry it.
    public static func rows(
        _ rows: [LocalCatalogRow],
        filter: ModelCatalogFilter = ModelCatalogFilter(),
        origin: ModelCatalogOrigin = .onDevice
    ) -> [LocalCatalogRow] {
        // Named rather than `matches`, and the callee qualified: a local named `matches` in the
        // closure's scope makes Swift 6.2 resolve the bare call to that value instead of to the
        // function, which fails the host job (run 44162622852 was that bug in another file).
        let kept = rows.filter { ModelCatalogQuery.keeps($0, by: filter) }
        let ordered = LocalCatalogQuery.sorted(kept, sort: filter.sort)
        // Checked against the whole list rather than the kept rows: a name that is curated but hidden
        // by a chip is still a curated model, not a second card for the same thing.
        guard let offered = ModelCatalogQuery.customRow(search: filter.search, in: rows, origin: origin)
        else { return ordered }
        return ordered + [offered]
    }

    public static func keeps(_ row: LocalCatalogRow, by filter: ModelCatalogFilter) -> Bool {
        guard row.covers(filter.capabilities) else { return false }
        return LocalCatalogQuery.matches(row, search: filter.search)
    }

    /// The card for a name the curated list does not carry, or nil when the text matches a card, is
    /// empty, or is not shaped like something this destination can install.
    ///
    /// A phone needs `owner/repository`; an Ollama server needs a tag, and a bare word is a valid tag
    /// and an invalid repository. The shape rule is therefore per-origin: offering `my-model` to a
    /// phone would be a request that fails for a reason the person cannot see.
    public static func customRow(
        search: String,
        in rows: [LocalCatalogRow],
        origin: ModelCatalogOrigin
    ) -> LocalCatalogRow? {
        let name = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count > 0, name.count <= maximumNameLength else { return nil }
        guard matchesShape(name, origin: origin) else { return nil }
        // Checked against the *unfiltered* library: a name that is curated but hidden by a chip is a
        // curated model, not a second card for the same thing.
        let hidden = rows.filter { LocalCatalogQuery.matches($0, search: name) }
        guard hidden.isEmpty else { return nil }
        return LocalCatalogRow(
            repoID: name,
            displayName: name,
            summary: origin.landsOnThisPhone
                ? "Not in Cairn's library. The exact repository is fetched from Hugging Face, "
                    + "checked against its published checksum, and stored on this phone."
                : "Not in Cairn's library. This exact name is sent to the server, which answers "
                    + "with what it can install under that name.",
            origin: .custom
        )
    }

    /// The name shapes each destination accepts, and nothing more.
    static func matchesShape(_ name: String, origin: ModelCatalogOrigin) -> Bool {
        if name.isEmpty || name.contains(" ") || name.contains("\n") || name.count > maximumNameLength {
            return false
        }
        switch origin {
        case .onDevice:
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        case .ollamaLibrary, .custom:
            return !name.contains("/")
        }
    }
}
