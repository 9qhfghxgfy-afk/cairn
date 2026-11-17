import Foundation
import Observation

/// Live view of `ServerSelection`, shared by the Servers screen and the chat session so one
/// tap in either place is immediately true in the other.
///
/// Every change writes through: an instant switch that evaporates on relaunch is not instant.
/// A failed write is recorded as `lastError` and the in-memory value is kept — the user's tap
/// must take effect even when the disk is briefly unhappy.
@Observable @MainActor
public final class ServerSelectionModel {
    public private(set) var selection: ServerSelection
    public private(set) var lastError: String?

    private let storing: any ServerSelectionStoring

    public init(storing: any ServerSelectionStoring) {
        self.storing = storing
        // A store that cannot be read is not a reason to lose the session: start unselected.
        self.selection = (try? storing.selection()) ?? ServerSelection()
    }

    public var activeProfileID: UUID? { selection.activeProfileID }

    public func lastModel(forProfile id: UUID) -> String? { selection.lastModel(forProfile: id) }

    public func activeProfile(in profiles: [ServerProfile]) -> ServerProfile? {
        selection.activeProfile(in: profiles)
    }

    public func setActive(_ id: UUID?) { mutate { $0.setActive(id) } }

    public func remember(modelID: String, forProfile id: UUID) {
        mutate { $0.remember(modelID: modelID, forProfile: id) }
    }

    public func forget(_ id: UUID) { mutate { $0.forgetProfile(id) } }

    public func reload() {
        do {
            selection = try storing.selection()
        } catch {
            lastError = "Could not read the saved server choice: \(error.localizedDescription)"
        }
    }

    /// Applies a change and writes it through, skipping the disk entirely when nothing changed —
    /// which matters because the model list re-records the current model on every load.
    private func mutate(_ change: (inout ServerSelection) -> Void) {
        var updated = selection
        change(&updated)
        guard updated != selection else { return }
        selection = updated
        do {
            try storing.saveSelection(updated)
        } catch {
            lastError = "Could not save the server choice: \(error.localizedDescription)"
        }
    }
}
