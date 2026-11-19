import Foundation

/// Which providers the user has agreed to send queries to, and which they have refused.
///
/// The app-wide outbound acknowledgement and this are two different questions, and collapsing them is how
/// consent becomes a formality. The acknowledgement says *Cairn may use the network for tools*. This says
/// *this particular third party may receive my queries* — which matters the moment the active provider can
/// change. A user who agreed to DuckDuckGo has not agreed to a company running a public instance they were
/// handed a URL for, and a grant stored against "search" in general would let that query go out anyway.
///
/// A refusal is stored as deliberately as a grant, so declining means something: the tool keeps returning
/// a typed refusal instead of asking again every turn until the user gives in.
///
/// Nothing here is a secret and nothing is a query — a set of keys. It is safe to persist, which is the
/// point.
public struct WebSearchConsentState: Sendable, Equatable, Codable {
    public enum Decision: String, Sendable, Equatable, Codable {
        /// Granted, so the search may run.
        case granted
        /// Declined, so the search is refused without asking again.
        case denied
        /// Never asked, or the provider is new.
        case undecided
    }

    public private(set) var grantedKeys: Set<String>
    public private(set) var deniedKeys: Set<String>

    public init(grantedKeys: Set<String> = [], deniedKeys: Set<String> = []) {
        self.grantedKeys = grantedKeys
        self.deniedKeys = deniedKeys
    }

    public static let `default` = WebSearchConsentState()

    /// Keyed by provider id and kind, so editing a provider into a different one cannot inherit a grant:
    /// a row repointed at someone else's instance is a different third party even though the row is the
    /// same row.
    public static func key(
        providerID: UUID,
        kind: WebSearchProviderKind
    ) -> String { "\(kind.rawValue):\(providerID.uuidString)" }

    public func decision(for profile: WebSearchProviderProfile) -> Decision {
        let key = Self.key(providerID: profile.id, kind: profile.kind)
        if deniedKeys.contains(key) { return .denied }
        // A provider on the user's own network is not a third party, so the acknowledgement they already
        // gave covers it; a second prompt would train them to tap through a sheet that asks nothing.
        if !profile.reachesPublicInternet { return .granted }
        return grantedKeys.contains(key) ? .granted : .undecided
    }

    /// Whether a search through this provider has to be asked about first.
    public func requiresPrompt(for profile: WebSearchProviderProfile) -> Bool {
        decision(for: profile) == .undecided
    }

    public mutating func grant(_ profile: WebSearchProviderProfile) {
        let key = Self.key(providerID: profile.id, kind: profile.kind)
        grantedKeys.insert(key)
        deniedKeys.remove(key)
    }

    /// Records a refusal and withdraws any earlier grant, which is what "change my mind" has to mean for a
    /// provider that was granted before its address was edited.
    public mutating func deny(_ profile: WebSearchProviderProfile) {
        let key = Self.key(providerID: profile.id, kind: profile.kind)
        deniedKeys.insert(key)
        grantedKeys.remove(key)
    }

    public mutating func revoke(providerID: UUID, kind: WebSearchProviderKind) {
        let key = Self.key(providerID: providerID, kind: kind)
        grantedKeys.remove(key)
        deniedKeys.remove(key)
    }

    /// Drops consent for a provider that no longer exists, so a deleted instance's grant cannot outlive
    /// the row it was given to.
    public mutating func removingProviders(notIn store: WebSearchProviderStore) {
        let live = Set(store.providers.map {
            Self.key(providerID: $0.id, kind: $0.kind)
        })
        grantedKeys.formIntersection(live)
        deniedKeys.formIntersection(live)
    }
}
