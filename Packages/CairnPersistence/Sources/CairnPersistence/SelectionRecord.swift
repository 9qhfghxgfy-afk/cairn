import Foundation
import SwiftData
import CairnChatDomain

/// On-disk shape of "which server is answering, and what each server was last used with".
///
/// One singleton row, not one row per server: the selection is app state — a pointer plus a
/// small map — and a single row makes "the active server" impossible to store twice. The last
/// model is keyed by profile id, so two servers that happen to offer a model with the same name
/// still remember their own choice.
///
/// Nothing here is secret. A model name and a UUID describe what the user pointed at, and both
/// stay on the device.
@Model
public final class ServerSelectionRecord {
    /// Unique so a bug cannot create a second "active server" row.
    @Attribute(.unique) public var slot: Int
    public var activeProfileID: UUID?
    public var lastModelJSON: Data?
    /// Which weights folder on this phone the chat was last pointed at. Kept out of `lastModelJSON`
    /// because that blob is keyed by server profile and an on-device model belongs to no profile.
    public var onDeviceModelID: String?
    public var updatedAt: Date

    public init(
        slot: Int = 0,
        activeProfileID: UUID? = nil,
        lastModelJSON: Data? = nil,
        onDeviceModelID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.slot = slot
        self.activeProfileID = activeProfileID
        self.lastModelJSON = lastModelJSON
        self.onDeviceModelID = onDeviceModelID
        self.updatedAt = updatedAt
    }
}

extension ServerSelectionRecord {
    func toSelection() -> ServerSelection {
        ServerSelection(
            activeProfileID: activeProfileID,
            lastModelIDs: JSONCodec.decode([UUID: String].self, from: lastModelJSON) ?? [:],
            onDeviceModelID: onDeviceModelID
        )
    }

    func apply(_ selection: ServerSelection, now: Date) {
        activeProfileID = selection.activeProfileID
        // An empty map stays nil rather than storing an empty blob.
        lastModelJSON = selection.lastModelIDs.isEmpty
            ? nil
            : JSONCodec.encode(selection.lastModelIDs)
        onDeviceModelID = selection.onDeviceModelID
        updatedAt = now
    }
}
