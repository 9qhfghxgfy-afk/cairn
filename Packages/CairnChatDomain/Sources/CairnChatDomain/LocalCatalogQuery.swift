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
    case recommended
    case smallest
    case newest
    case largest
    case name

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .recommended: return "Recommended"
        case .smallest: return "Smallest download"
        case .newest: return "Newest"
        case .largest: return "Largest"
        case .name: return "Name"
        }
    }
}

public enum LocalCatalogQuery {
    /// Bytes a download has to be under for the "Under 4 GB" chip to keep it. Decimal gigabytes,
    /// because that is what a publisher's stated size means and what the Files app shows.
    static let smallCeilingBytes: Int64 = 4_000_000_000

    public static func rows(
        _ rows: [LocalCatalogRow],
        chip: LocalFilterChip = .all,
        search: String = "",
        sort: LocalSortOrder = .recommended
    ) -> [LocalCatalogRow] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kept = rows.filter { row in
            if let label = chip.requiredLabel, !row.capabilityLabels.contains(label) { return false }
            // An entry that states no size is kept by the size chip: "unknown" is not "too big", and
            // dropping it would hide a model the person could perfectly well download.
            if chip == .small, let bytes = row.downloadBytes, bytes >= smallCeilingBytes { return false }
            if needle.isEmpty { return true }
            return row.displayName.lowercased().contains(needle)
                || row.repoID.lowercased().contains(needle)
                || row.capabilityLabels.contains { $0.lowercased().contains(needle) }
        }
        return sorted(kept, sort: sort)
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
            return rows.sorted { size($0) < size($1) }
        case .largest:
            return rows.sorted { size($0) > size($1) }
        case .newest:
            return rows.sorted { $0.addedOn > $1.addedOn }
        case .name:
            return rows.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    /// 0 for something small that publishes tools, 1 for something small that does not, 2 for a
    /// capable-but-large entry, 3 for an entry whose size nobody stated.
    static func rank(_ row: LocalCatalogRow) -> Int {
        guard let bytes = row.downloadBytes else { return 3 }
        let capable = row.capabilityLabels.contains("Tools")
        if bytes < smallCeilingBytes { return capable ? 0 : 1 }
        return capable ? 2 : 3
    }

    /// An unstated size is never read as zero bytes: it sorts after every stated size when the list
    /// goes up and before every stated size when it goes down. Either way it is not offered as the
    /// cheapest thing in the library, which is what treating "nobody said" as zero would do.
    static func size(_ row: LocalCatalogRow) -> Int64 {
        row.downloadBytes ?? Int64.max
    }
}
