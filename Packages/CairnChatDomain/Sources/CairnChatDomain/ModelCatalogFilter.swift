import Foundation

/// What the Download tab is currently narrowed to.
///
/// Held as one value rather than as three loose view properties so the rules — chips narrow, they
/// never widen; a search means more than the display name — live in one place and can be proved
/// without a view. A filter guessed at inside a view is a filter nobody can prove: a `Vision` chip
/// that also kept the text-only models would promise a capability the phone then fails to use, and
/// that is invisible in a screenshot.
public struct ModelCatalogFilter: Sendable, Equatable {
    /// Free text from the search field, matched through `LocalCatalogQuery.matches`.
    public var search: String
    /// Every listed capability must be stated by the entry. An empty set keeps everything.
    public var capabilities: Set<ModelCatalogCapability>
    public var sort: LocalSortOrder

    public init(
        search: String = "",
        capabilities: Set<ModelCatalogCapability> = [],
        sort: LocalSortOrder = .popular
    ) {
        self.search = search
        self.capabilities = capabilities
        self.sort = sort
    }

    public var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True when nothing has been narrowed, which lets the empty-state copy say the chips are what
    /// emptied the list rather than blaming the library.
    public var isNarrowed: Bool { !trimmedSearch.isEmpty || !capabilities.isEmpty }

    /// Toggles one chip, so "tap it again to take the requirement off" is one behaviour with one
    /// owner rather than a line of view code that can drift per screen.
    public mutating func toggle(_ capability: ModelCatalogCapability) {
        if capabilities.contains(capability) { capabilities.remove(capability) }
        else { capabilities.insert(capability) }
    }

    public func toggling(_ capability: ModelCatalogCapability) -> ModelCatalogFilter {
        var copy = self
        copy.toggle(capability)
        return copy
    }

    public func filtering(_ capability: ModelCatalogCapability) -> Bool {
        capabilities.contains(capability)
    }

    /// Clears the narrowing but keeps the chosen order: someone who sorted by size and then cleared
    /// the chips meant the order, and resetting it would answer a question they did not ask.
    public mutating func clearNarrowing() {
        search = ""
        capabilities.removeAll()
    }
}
