import Foundation
import SwiftData
import CairnChatDomain

/// App-wide settings on the same container as the chats.
///
/// Same store, one singleton row: the Default Configuration, the theme and the appearance are read and
/// written together as one value, and splitting them across stores could leave a default configuration
/// disagreeing with the theme that was being edited beside it.
extension SwiftDataStore: AppSettingsStoring {
    public func appSettings() throws -> AppSettings {
        guard let record = try fetchSettings() else { return .default }
        return record.toSettings()
    }

    /// Whole-value write on purpose. A half-written setting is worse than a lost one here: a default
    /// configuration that only partly landed would seed new chats with something the user never chose.
    public func saveAppSettings(_ settings: AppSettings) throws {
        let record = try fetchSettings() ?? insertSettingsRecord()
        record.apply(settings, now: Date())
        do {
            try context.save()
        } catch {
            // Typed reason only — settings content never reaches a log.
            throw StoreError.writeFailed("Could not save the app settings.")
        }
    }

    /// The one settings row, created on first write. Row 0 is the only slot today; naming it in the
    /// predicate keeps a second settings-shaped value from being squeezed into the same row later.
    private func insertSettingsRecord() -> SettingsRecord {
        let fresh = SettingsRecord(slot: settingsSlot)
        context.insert(fresh)
        return fresh
    }

    private func fetchSettings() throws -> SettingsRecord? {
        let slot = settingsSlot
        var descriptor = FetchDescriptor<SettingsRecord>(predicate: #Predicate { $0.slot == slot })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// The singleton row the app-wide settings occupy.
private let settingsSlot = 0
