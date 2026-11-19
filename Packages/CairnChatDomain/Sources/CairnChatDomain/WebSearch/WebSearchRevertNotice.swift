import Foundation

/// The line Settings shows when selection was moved off a provider by something other than the user.
///
/// A silent reversion is the failure mode this exists to prevent. If a SearXNG row is deleted, or the
/// cloud profile carrying a key is removed, search starts going somewhere else — and if the user is not
/// told, the next result they read looks identical to one from the provider they chose. So the reason is
/// stored, not just performed, and it stays on screen until it is dismissed.
public struct WebSearchRevertNotice: Sendable, Equatable, Codable {
    public enum Reason: String, Sendable, Equatable, Codable {
        /// The user deleted the row that was active.
        case providerRemoved
        /// The cloud profile, or the key under it, went away and its row went with it.
        case cloudKeyRemoved
        /// A stored selection named a provider this build cannot find — a settings blob from a build or
        /// a device that had a row this one does not.
        case selectionLost
    }

    public var reason: Reason
    /// The provider's own name, so the notice can say what is gone. Never an address.
    public var providerName: String
    public var at: Date

    public init(reason: Reason, providerName: String, at: Date = Date()) {
        self.reason = reason
        self.providerName = providerName
        self.at = at
    }

    /// The sentence in Settings. It names the new provider too: "reverted" alone leaves the user to
    /// work out where the queries are going now.
    public var text: String {
        let cause: String
        switch reason {
        case .providerRemoved:
            cause = "you deleted \(providerName)"
        case .cloudKeyRemoved:
            cause = "the Ollama Cloud profile or its key was removed"
        case .selectionLost:
            cause = "this device no longer has \(providerName)"
        }
        return "Web search reverted to DuckDuckGo because \(cause)."
    }
}
