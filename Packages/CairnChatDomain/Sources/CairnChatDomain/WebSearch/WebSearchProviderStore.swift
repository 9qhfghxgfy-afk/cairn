import Foundation

/// The provider list, which row is active, and why selection moved — as one value.
///
/// The list always contains the built-in DuckDuckGo row, and `active` can never name something that is
/// not in the list. Both rules are enforced in the initialiser rather than at the call sites, because this
/// value is decoded from disk: a blob written by another build, or a row removed under a live selection,
/// has to read back as a store that can still search — and has to say out loud that selection moved.
///
/// Nothing here chooses a provider on its own. There is no precedence and no fallback: a failing provider
/// is a typed failure, and only a person changes which row is active.
public struct WebSearchProviderStore: Sendable, Equatable, Codable {
    /// The rows, in list order. `internal(set)` rather than `private(set)` so the cloud reconciliation in
    /// `+Cloud.swift` can do its job; from outside this module the list is read-only either way, and every
    /// write path inside it runs through the anchoring rule in `init`.
    public internal(set) var providers: [WebSearchProviderProfile]
    public internal(set) var activeProviderID: UUID
    public internal(set) var revertNotice: WebSearchRevertNotice?

    /// The name a lost selection is reported under. The row is gone, so its name is gone with it — the
    /// notice says what happened rather than guessing at what was lost.
    static let lostSelectionName = "the provider that was selected"

    public init(
        providers: [WebSearchProviderProfile] = [],
        activeProviderID: UUID? = nil,
        revertNotice: WebSearchRevertNotice? = nil
    ) {
        let anchor = providers.first(where: \.isBuiltIn) ?? .builtIn
        // Built-in first: it is the row the list is anchored to, and a list that shows it last reads as
        // though it were one more optional instance.
        let rows = [anchor] + providers.filter { !$0.isBuiltIn }
        let known = activeProviderID.flatMap { id in
            rows.contains { $0.id == id } ? id : nil
        }
        self.providers = rows
        self.activeProviderID = known ?? anchor.id
        self.revertNotice = revertNotice
    }

    public static let `default` = WebSearchProviderStore()

    /// The one provider a search may use. Resolving through here means no call site has to re-check that
    /// the id still names a row.
    public var active: WebSearchProviderProfile {
        providers.first { $0.id == activeProviderID } ?? .builtIn
    }

    public func profile(id: UUID) -> WebSearchProviderProfile? {
        providers.first { $0.id == id }
    }

    /// Every row the user added, in the order they added it. The built-in row is shown separately, which
    /// is what keeps "delete" off the one row that cannot be deleted.
    public var userRows: [WebSearchProviderProfile] { providers.filter { !$0.isBuiltIn } }

    /// Selecting a row is also how a revert notice is cleared: the user has now chosen, so there is
    /// nothing left to warn about.
    public mutating func select(id: UUID) {
        guard let row = profile(id: id) else {
            // A stale id means the row went away while something held its id. Fall back to the built-in
            // row and say so, rather than searching a provider nobody selected.
            revertToBuiltIn(reason: .selectionLost, providerName: Self.lostSelectionName)
            return
        }
        activeProviderID = row.id
        revertNotice = nil
    }

    /// Adds a row the user created, after validating it, and makes it active.
    ///
    /// A new provider becomes the active one because that is the only reason to add one, and because
    /// leaving it inactive would leave the built-in third party answering queries the user just arranged
    /// to avoid.
    public mutating func add(_ profile: WebSearchProviderProfile, now: Date = Date()) throws {
        try validated(profile, isUserAdded: true)
        var row = profile
        row.createdAt = now
        row.updatedAt = now
        providers.append(row)
        activeProviderID = row.id
        revertNotice = nil
    }

    /// Applies an edit to an existing row, re-validating the whole row rather than the changed field.
    ///
    /// A half-validated row is the failure this avoids: an edit that changes only the address still has to
    /// satisfy the credential rule that belongs to the kind, and an edit that changes only the kind's
    /// credential still has to satisfy the address rule the kind implies.
    public mutating func update(
        id: UUID,
        now: Date = Date(),
        change: (inout WebSearchProviderProfile) -> Void
    ) throws {
        guard var row = profile(id: id) else { return }
        change(&row)
        try validated(row, isUserAdded: false)
        row.updatedAt = now
        if let index = providers.firstIndex(where: { $0.id == id }) { providers[index] = row }
    }

    /// The one validation call, so an add and an edit cannot drift apart on which rules they apply.
    private func validated(
        _ row: WebSearchProviderProfile,
        isUserAdded: Bool
    ) throws {
        try WebSearchProviderValidator.validate(
            name: row.displayName, kind: row.kind, endpoint: row.baseURLString,
            categories: row.categories, language: row.language,
            timeoutSeconds: row.timeoutSeconds, credentialShape: row.credentialShape,
            hasCredential: row.hasCredential, customHeaders: row.customHeaders,
            isUserAdded: isUserAdded
        )
    }

    /// Deletes a row. The built-in row refuses, and deleting the active row reverts selection to it.
    ///
    /// The revert is stored as a notice, not just performed: search is about to start going somewhere the
    /// user did not pick, and results from DuckDuckGo look exactly like results from anything else.
    @discardableResult
    public mutating func remove(id: UUID) throws -> WebSearchProviderProfile? {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return nil }
        let row = providers[index]
        guard !row.isBuiltIn else { throw WebSearchProviderValidationError.builtInIsPermanent }
        providers.remove(at: index)
        if activeProviderID == row.id {
            revertToBuiltIn(reason: .providerRemoved, providerName: row.displayName)
        }
        return row
    }

    /// Moves selection back to the built-in row and records why. One helper because there are three ways
    /// selection can move without the user asking (a row deleted, a cloud key removed, a stored id that
    /// names nothing), and a reversion nobody recorded is a silent change of provider.
    mutating func revertToBuiltIn(reason: WebSearchRevertNotice.Reason, providerName: String) {
        activeProviderID = WebSearchProviderProfile.builtInID
        revertNotice = WebSearchRevertNotice(reason: reason, providerName: providerName)
    }

    /// Clears the notice once it has been read. It is not cleared by a search succeeding — the user should
    /// have to acknowledge the change, not have it fade out under them.
    public mutating func dismissRevertNotice() { revertNotice = nil }

    private enum CodingKeys: String, CodingKey {
        case providers, activeProviderID, revertNotice
    }

    /// Decoding goes through the same anchoring rule as construction, and reports a lost selection.
    ///
    /// Synthesised decoding would happily produce a store whose active id names nothing, which is a
    /// settings file that quietly changes where queries go.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try box.decodeIfPresent([WebSearchProviderProfile].self, forKey: .providers) ?? []
        let wanted = try box.decodeIfPresent(UUID.self, forKey: .activeProviderID)
        let stored = try box.decodeIfPresent(WebSearchRevertNotice.self, forKey: .revertNotice)
        self.init(providers: rows, activeProviderID: wanted, revertNotice: stored)
        if let wanted, activeProviderID != wanted, revertNotice == nil {
            revertToBuiltIn(reason: .selectionLost, providerName: Self.lostSelectionName)
        }
    }
}

