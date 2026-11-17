import Foundation
import SwiftData
import CairnChatDomain

/// The active-server choice and each server's last model live in the same container as the chat
/// and the profiles: one container, one writer, so a server switch cannot race a profile write.
///
/// Deleting a server is the App's job (`ServerProfileStoring.delete` plus
/// `ServerSelectionModel.forget`), but the read path prunes anyway: a remembered model for a
/// profile that no longer exists must not survive a relaunch, because "no trace of a deleted
/// server" should hold even if a caller forgets to say so.
extension SwiftDataStore: ServerSelectionStoring {
    public func selection() throws -> ServerSelection {
        let stored = record().toSelection()
        let known = Set(try profiles().map(\.id))
        var pruned = stored
        pruned.lastModelIDs = pruned.lastModelIDs.filter { known.contains($0.key) }
        if let active = pruned.activeProfileID, !known.contains(active) {
            pruned.activeProfileID = nil
        }
        return pruned
    }

    public func saveSelection(_ selection: ServerSelection) throws {
        let row = record()
        row.apply(selection, now: Date())
        try context.save()
    }

    /// Fetches the singleton, creating it on first use. Written rather than lazily cached so a
    /// fresh context after relaunch always reads what is actually on disk.
    private func record() -> ServerSelectionRecord {
        var descriptor = FetchDescriptor<ServerSelectionRecord>(predicate: #Predicate { $0.slot == 0 })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let created = ServerSelectionRecord()
        context.insert(created)
        return created
    }
}
