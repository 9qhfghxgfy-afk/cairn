import Foundation

/// How the on-device library is narrowed and ordered.
///
/// A list of thirty-odd repositories in a screen built for a phone is only readable when it can be
/// narrowed, so the chips and the search field decide what shows. The rules live here rather than in
/// the view because a filter guessed at in a view is a filter no test can prove: "Small" that also
/// hides the one model that fits, or a search that matches a display name but not the repository the
/// user meant to type, are both invisible until someone looks.
public enum LocalFilterChip: String, Sendable, Equatable, CaseIterable, Identifiable {
    case all
    case capable
    case visual
    case thinking
    case small

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All"
        case .capable: return "Tool calling"
        case .visual: return "Vision"
        case .thinking: return "Reasoning"
        case .small: return "Under 4 GB"
        }
    }

    /// The capability name this chip requires, or nil when the chip is not about a capability.
    /// Compared against the published labels, which are the same words the badges draw.
    var requiredLabel: String? {
        switch self {
        case .capable: return "Tools"
        case .visual: return "Vision"
        case .thinking: return "Thinking"
        case .all, .small: return nil
        }
    }
}

public enum LocalSortOrder: String, Sendable, Equatable, CaseIterable, Identifiable {
    case popular
    case recommended
    case smallest
    case newest
    case largest
    case name

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .popular: return "Popular"
        case .recommended: return "Best for this phone"
        case .smallest: return "Smallest download"
        case .newest: return "Newest"
        case .largest: return "Largest"
        case .name: return "Name"
        }
    }

    /// The four orders the Download tab offers. `recommended` and `name` stay available to any other
    /// list built on these rows without adding a fifth choice to a menu a thumb has to reach.
    public static let downloadOrders: [LocalSortOrder] = [.popular, .newest, .smallest, .largest]
}

public enum LocalCatalogQuery {
    /// Bytes a download has to be under for the "Under 4 GB" chip to keep it. Decimal gigabytes,
    /// because that is what a publisher's stated size means and what the Files app shows.
    static let smallCeilingBytes: Int64 = 4_000_000_000

    public static func rows(
        _ rows: [LocalCatalogRow],
        chip: LocalFilterChip = .all,
        search: String = "",
        sort: LocalSortOrder = .popular
    ) -> [LocalCatalogRow] {
        let kept = rows.filter { row in
            if let label = chip.requiredLabel, !row.capabilityLabels.contains(label) { return false }
            // An entry that states no size is kept by the size chip: "unknown" is not "too big", and
            // dropping it would hide a model the person could perfectly well download.
            if chip == .small, let bytes = row.downloadBytes, bytes >= smallCeilingBytes { return false }
            return matches(row, search: search)
        }
        return sorted(kept, sort: sort)
    }

    /// Whether a row is what a search box is asking for. Display name and repository first, then the
    /// family and publisher names, because someone typing `gemma` or `Qwen` means the family.
    ///
    /// Public because the Download tab filters by several capabilities on top of this, and one
    /// matching rule shared by both paths is the only reason the two cannot disagree about what the
    /// same words mean.
    public static func matches(_ row: LocalCatalogRow, search: String) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return true }
        let haystack = [
            row.displayName, row.repoID, row.capabilityLabels.joined(separator: " "),
            row.series ?? "", row.provider ?? "", row.summary
        ].joined(separator: " ").lowercased()
        return haystack.contains(needle)
    }

    /// A search that looks like a repository and matches nothing in the curated list, returned as the
    /// repository to fetch anyway.
    ///
    /// Cairn's curated list is short; Hugging Face is not. When someone types `org/repo` and the list
    /// answers "nothing here", the honest reply is "then take that repository" — not a dead end that
    /// reads as a broken search. nil for anything not shaped like a repository, and nil when the
    /// curated list already has it, so a known entry is never offered twice.
    public static func unlistedRepoID(search: String, in rows: [LocalCatalogRow]) -> String? {
        let candidate = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = candidate.split(separator: "/")
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") })
        else { return nil }
        let repoID = String(parts[0] + "/" + parts[1])
        return rows.contains { $0.repoID.caseInsensitiveCompare(repoID) == .orderedSame } ? nil : repoID
    }

    static func sorted(_ rows: [LocalCatalogRow], sort: LocalSortOrder) -> [LocalCatalogRow] {
        switch sort {
        case .popular:
            // Cairn's curated rank first. Where two entries carry the same rank — which is every row
            // nobody ranked, since 0 is the default — the phone-first heuristic below decides, so an
            // unranked list still orders usefully instead of arriving in whatever order the list
            // happened to be built in.
            return rows.sorted { lhs, rhs in
                let left = curation(lhs), right = curation(rhs)
                if left != right { return left < right }
                let leftFit = rank(lhs), rightFit = rank(rhs)
                if leftFit != rightFit { return leftFit < rightFit }
                if size(lhs) != size(rhs) { return size(lhs) < size(rhs) }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                    == .orderedAscending
            }
        case .recommended:
            // Capable and small first: what a phone can hold and what a phone can use with tools *is*
            // the recommendation for a phone. An entry that states no size sorts last, because
            // "unstated" is not "small".
            return rows.sorted { lhs, rhs in
                let left = rank(lhs), right = rank(rhs)
                if left != right { return left < right }
                return size(lhs) < size(rhs)
            }
        case .smallest:
            return bySize(rows, descending: false)
        case .largest:
            return bySize(rows, descending: true)
        case .newest:
            // Two entries added on the same day are ordered by name rather than by whatever position
            // the curated list happened to put them in, so the same library always draws the same list.
            return rows.sorted {
                if $0.addedOn != $1.addedOn { return $0.addedOn > $1.addedOn }
                return nameFirst($0, $1)
            }
        case .name:
            return rows.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    /// Cairn's curated rank for the `Popular` order. A row that was never ranked carries 0, which is
    /// a real rank for whoever curated it — so the tie-break in `.popular` is what keeps an unranked
    /// list from ordering by file position.
    static func curation(_ row: LocalCatalogRow) -> Int { row.sortOrder }

    /// 0 for something small that publishes tools, 1 for something small that does not, 2 for a
    /// capable-but-large entry, 3 for an entry whose size nobody stated.
    static func rank(_ row: LocalCatalogRow) -> Int {
        guard let bytes = row.downloadBytes else { return 3 }
        let capable = row.capabilityLabels.contains("Tools")
        if bytes < smallCeilingBytes { return capable ? 0 : 1 }
        return capable ? 2 : 3
    }

    /// Size order with the unstated size pinned to the bottom in *both* directions.
    ///
    /// Reading "nobody stated a size" as `Int64.max` would put such an entry first in a Largest list,
    /// which offers the person the one entry Cairn knows least about as the biggest commitment in the
    /// library — the worst possible moment to guess. A stated size always gets offered first; the
    /// unknown ones keep their own order by name.
    static func bySize(_ rows: [LocalCatalogRow], descending: Bool) -> [LocalCatalogRow] {
        rows.sorted { lhs, rhs in
            switch (lhs.downloadBytes, rhs.downloadBytes) {
            case (let left?, let right?):
                if left != right { return descending ? left > right : left < right }
                return nameFirst(lhs, rhs)
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return nameFirst(lhs, rhs)
            }
        }
    }

    static func nameFirst(_ lhs: LocalCatalogRow, _ rhs: LocalCatalogRow) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    /// An unstated size is never read as zero bytes: it sorts after every stated size, in every order
    /// that uses this. Either reading of "nobody said" as a number would offer the entry as the
    /// cheapest or the dearest thing in the library, and neither is known.
    static func size(_ row: LocalCatalogRow) -> Int64 {
        row.downloadBytes ?? Int64.max
    }
}
