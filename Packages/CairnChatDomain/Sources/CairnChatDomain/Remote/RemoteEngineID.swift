import Foundation

/// The engine id a saved profile gets once it is registered: `remote:<profile uuid>`.
///
/// One place owns that string. The switcher, the session, and the model service all need to go
/// from a profile to its engine and back, and a hand-built literal in each of them is how a
/// switch silently stops working.
public enum RemoteEngineID: Sendable {
    public static let prefix = "remote:"

    public static func make(profileID: UUID) -> String { prefix + profileID.uuidString }

    /// nil for any engine that is not a saved server — the mock, or a later on-device engine.
    public static func parse(_ engineID: String) -> UUID? {
        guard engineID.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(engineID.dropFirst(prefix.count)))
    }
}

extension ServerProfile {
    /// The id this profile's engine is registered under.
    public var engineID: String { RemoteEngineID.make(profileID: id) }
}

public extension InferenceProvider {
    /// The saved server this engine came from, or nil for an engine that is not a server profile.
    /// Declared with a default so an on-device or mock engine need not know the concept exists.
    var serverProfileID: UUID? { nil }
}
