import Foundation

/// Which server answers the next turn, and the last model each server was used with.
///
/// The last model is **per server**, which is the whole point: switching to the box that runs a
/// 30B model must not carry over the small model name typed for the laptop across the room. A
/// model name that does not exist on the target server would fail the turn, so it is never
/// shared between servers.
public struct ServerSelection: Sendable, Equatable {
    public var activeProfileID: UUID?
    public var lastModelIDs: [UUID: String]

    public init(activeProfileID: UUID? = nil, lastModelIDs: [UUID: String] = [:]) {
        self.activeProfileID = activeProfileID
        self.lastModelIDs = lastModelIDs
    }

    public func lastModel(forProfile id: UUID) -> String? { lastModelIDs[id] }

    public mutating func setActive(_ id: UUID?) { activeProfileID = id }

    public mutating func remember(modelID: String, forProfile id: UUID) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastModelIDs[id] = trimmed
    }

    /// A deleted server leaves no trace: neither an active pointer nor a remembered model.
    public mutating func forgetProfile(_ id: UUID) {
        if activeProfileID == id { activeProfileID = nil }
        lastModelIDs[id] = nil
    }

    /// The active server, but only while it is still configured and actually able to answer —
    /// a disabled or un-opted-in profile cannot be the active one.
    public func activeProfile(in profiles: [ServerProfile]) -> ServerProfile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first { $0.id == id && $0.usableNow }
    }

    /// What should be active after a launch or a deletion: the stored choice when it still works,
    /// otherwise the first server that does. nil when none can answer.
    public func resolvedActive(in profiles: [ServerProfile]) -> ServerProfile? {
        if let chosen = activeProfile(in: profiles) { return chosen }
        return profiles.first(where: \.usableNow)
    }
}
