import Foundation

/// Sort and filter for the Download tab. Pure, so the chips and the sort menu are testable without
/// a view.
public enum CatalogSort: String, Sendable, Equatable, CaseIterable, Identifiable {
    case newest
    case smallest
    case largest
    case name

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .newest: return "Newest"
        case .smallest: return "Smallest download"
        case .largest: return "Largest"
        case .name: return "Name"
        }
    }
}

public struct CatalogFilter: Sendable, Equatable {
    public var searchText: String
    /// Every listed capability must be present — chips narrow, they do not widen.
    public var requiredCapabilities: Set<ModelCapability>

    public init(searchText: String = "", requiredCapabilities: Set<ModelCapability> = []) {
        self.searchText = searchText
        self.requiredCapabilities = requiredCapabilities
    }

    public var isEmpty: Bool { searchText.isEmpty && requiredCapabilities.isEmpty }
}

public enum CatalogQuery {
    public static func apply(
        _ filter: CatalogFilter,
        sort: CatalogSort = .newest,
        entries: [OnDeviceCatalogEntry] = OnDeviceCatalog.entries
    ) -> [OnDeviceCatalogEntry] {
        let matches = entries.filter { matches($0, by: filter) }
        // A typed repo ID that is not in the library still has to be installable, which is what
        // "Not in the library? Type the exact name to install" promises.
        let unlisted = unlistedMatch(for: filter.searchText, excluding: entries)
        return sorted(sort, matches + unlisted)
    }

    public static func matches(_ entry: OnDeviceCatalogEntry, by filter: CatalogFilter) -> Bool {
        let text = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let haystack = "\(entry.displayName) \(entry.repoID) \(entry.parameterSize ?? "")"
                .lowercased()
            guard haystack.contains(text.lowercased()) else { return false }
        }
        return requiredCapabilities(of: entry).isSuperset(of: filter.requiredCapabilities)
    }

    static func requiredCapabilities(of entry: OnDeviceCatalogEntry) -> Set<ModelCapability> {
        Set(entry.capabilities)
    }

    /// Turns free text into one installable entry when it is a well-formed repo ID the curated
    /// list does not carry. Anything else yields nothing — a malformed name is not a model.
    public static func unlistedMatch(
        for searchText: String,
        excluding entries: [OnDeviceCatalogEntry] = OnDeviceCatalog.entries
    ) -> [OnDeviceCatalogEntry] {
        let candidate = HuggingFaceRepoID.parse(searchText)
        guard case .valid(let repoID) = candidate,
              !entries.contains(where: { $0.repoID == repoID })
        else { return [] }
        return [.unlisted(repoID: repoID)]
    }

    static func sorted(
        _ sort: CatalogSort,
        _ entries: [OnDeviceCatalogEntry]
    ) -> [OnDeviceCatalogEntry] {
        switch sort {
        case .newest:
            return entries.sorted { $0.addedToLibrary > $1.addedToLibrary }
        case .smallest:
            return entries.sorted { $0.weightsBytes < $1.weightsBytes }
        case .largest:
            return entries.sorted { $0.weightsBytes > $1.weightsBytes }
        case .name:
            return entries.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }
}
