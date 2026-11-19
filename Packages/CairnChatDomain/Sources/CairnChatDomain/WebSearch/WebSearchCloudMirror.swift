import Foundation

/// What one Ollama Cloud server profile implies for the search provider list.
///
/// Ollama Cloud search is not a row anybody adds: it exists exactly as long as a cloud profile with a
/// key exists, and it has to disappear the moment that key does, or the app would keep offering a search
/// provider that can only fail. This struct is how the app layer says that without handing a secret to
/// the domain — it carries the presence of a key, never the key, in the same shape the rest of the
/// settings use to talk about credentials.
public struct WebSearchCloudMirror: Sendable, Equatable {
    public var sourceProfileID: UUID
    public var profileName: String
    public var hasKey: Bool

    public init(sourceProfileID: UUID, profileName: String, hasKey: Bool) {
        self.sourceProfileID = sourceProfileID
        self.profileName = profileName
        self.hasKey = hasKey
    }
}
