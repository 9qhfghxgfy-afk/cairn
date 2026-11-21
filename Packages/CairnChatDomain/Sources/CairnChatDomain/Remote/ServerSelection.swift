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
    /// Which model on this phone the chat was last pointed at.
    ///
    /// It is stored apart from `lastModelIDs` on purpose. Those are keyed by server profile because a
    /// model name means a different thing on each box; an on-device model has no server, so keying it
    /// under some profile's UUID would make "the phone's model" change whenever the active server did.
    /// One slot, and only the on-device engine reads it.
    public var onDeviceModelID: String?

    public init(
        activeProfileID: UUID? = nil,
        lastModelIDs: [UUID: String] = [:],
        onDeviceModelID: String? = nil
    ) {
        self.activeProfileID = activeProfileID
        self.lastModelIDs = lastModelIDs
        self.onDeviceModelID = onDeviceModelID
    }

    public func lastModel(forProfile id: UUID) -> String? { lastModelIDs[id] }

    public mutating func setActive(_ id: UUID?) { activeProfileID = id }

    public mutating func remember(modelID: String, forProfile id: UUID) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastModelIDs[id] = trimmed
    }

    /// Remembers the phone's model. An empty name is not a choice, so it writes nothing — the
    /// difference between "no choice yet" and "the choice was cleared" matters when a model is deleted.
    public mutating func rememberOnDevice(modelID: String) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onDeviceModelID = trimmed
    }

    /// Drops the remembered phone model, which is what deleting it owes: a stale name would otherwise
    /// come back as the choice on the next launch and fail the turn.
    public mutating func forgetOnDeviceModel() { onDeviceModelID = nil }

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
