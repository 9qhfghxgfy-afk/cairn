import Foundation
import CairnAppUI
import CairnChatDomain
import CairnInferenceLocal
import CairnInferenceNative

/// The phone's half of the Installed tab, behind the seam `CairnAppUI` reads.
///
/// This is the layer that is allowed to look at a folder and at a runtime. The view model asks what this
/// phone holds and gets entries; it never learns that `Application Support` exists. Two sources meet here —
/// the store's manifests and Apple's own availability reading — because the Installed tab is one list, and a
/// list assembled inside a view is a list no test can check.
///
/// Removal runs here rather than in the view model because the order is the safety: a resident model is
/// taken out of memory **before** its bytes are touched, and the thing that knows whether a turn is running
/// in that model is the registry, which a view model may not reach.
@MainActor
final class InstalledModelStore: InstalledModelServing {
    /// nil when this build has no place to keep models. A read then throws rather than reporting an empty
    /// list, because "you have no models" is a claim this build did not earn.
    let layout: ModelStoreLayout?
    let library: any LocalModelLibraryServicing
    /// nil when no runtime is attached. Deletion then still removes files — there is nothing resident to
    /// take back — but it cannot promise that no turn is running, which is what the registry is for.
    let registry: OnDeviceModelRegistry?
    let fileManager: FileManager
    /// Read at the moment the list is drawn, never cached: Apple Intelligence can be switched in Settings
    /// while Cairn sits in the background, and a row that outlives that switch is a row about a model this
    /// phone no longer offers.
    let appleAvailability: @MainActor () -> AppleModelAvailability
    /// Which runtime claims belong to a folder's format.
    ///
    /// The registry keys residents by **engine**, not by repository: the MLX engine holds one model at a
    /// time under `mlx-on-device`, whichever folder it loaded. So a folder's id is not what has to be
    /// evicted, and inventing a mapping here would be a guess about what the runtime decided to load.
    let residencyIDs: @MainActor (ModelFormat) -> [String]

    init(
        layout: ModelStoreLayout?,
        library: any LocalModelLibraryServicing,
        registry: OnDeviceModelRegistry?,
        fileManager: FileManager = .default,
        appleAvailability: @MainActor @escaping () -> AppleModelAvailability = {
            AppleModelAvailabilityReader.current()
        },
        residencyIDs: @MainActor @escaping (ModelFormat) -> [String] = { format in
            format == .mlx ? [MLXNativeProvider.modelID] : []
        }
    ) {
        self.layout = layout
        self.library = library
        self.registry = registry
        self.fileManager = fileManager
        self.appleAvailability = appleAvailability
        self.residencyIDs = residencyIDs
    }

    /// What this phone holds, then the model iOS built in.
    ///
    /// Sizes are re-read from the folder rather than taken from the install manifest. A manifest records
    /// what the download wrote; iOS can purge weights afterwards, and a Delete confirmation that promises
    /// back 3.4 GB this phone no longer has is a number nobody looked at. The manifest figure is kept only
    /// when the folder yields nothing — Cairn's own record beats no answer at all.
    func installedEntries() async throws -> [InstalledModelEntry] {
        let rows = try await library.installedRows()
        var found = InstalledInventory.entries(for: rows.map(measuredReading))
        if let system = appleEntry() { found.append(system) }
        return found
    }

    /// Takes one model back.
    ///
    /// Only a folder this app wrote on this device is ever removed, and that is decided here rather than
    /// trusted from the caller: a row built by hand for Apple's model or for a server's tag gets a refusal,
    /// not a best-effort attempt. The registry is asked first, so a model with a turn in flight is still
    /// mapped into memory when this throws and its files are untouched.
    func remove(_ entry: InstalledModelEntry) async throws {
        guard entry.host == .thisPhone, let repoID = entry.hostModelID else {
            throw entry.isSystemManaged
                ? InstalledModelError.systemManaged
                : InstalledModelError.notOnThisPhone
        }
        guard layout != nil else { throw InstalledModelError.storageUnavailable }
        try await releaseFromMemory(entry.format)
        // The library owns "what does deleting a model mean" — the folder and the resume blocks kept with
        // it, in the order that leaves a retry possible. A second answer written here is how a delete ends
        // up removing weights and leaving the blocks that point into them.
        try await library.delete(
            InstalledLocalModel(repoID: repoID, displayName: entry.displayName)
        )
    }

    // MARK: - Helpers

    private func measuredReading(_ row: InstalledLocalModel) -> InstalledLocalModel {
        guard let layout else { return row }
        let bytes = layout.sizeOnDisk(at: layout.directory(for: row.repoID), fileManager: fileManager)
        guard bytes > 0 else { return row }
        var copy = row
        copy.sizeBytes = bytes
        return copy
    }

    private func appleEntry() -> InstalledModelEntry? {
        let availability = appleAvailability()
        return InstalledInventory.appleIntelligence(
            available: availability.isUsable,
            reason: availability.reasonText
        )
    }

    /// Evicts every runtime claim a folder's format owns, refusing while a turn is in flight.
    ///
    /// A model that is not resident is not an error — deleting a model this app downloaded and never loaded
    /// is the ordinary case — and an idle one goes through the injected unloader, which is the only path
    /// that actually returns memory.
    private func releaseFromMemory(_ format: ModelFormat) async throws {
        guard let registry else { return }
        for modelID in residencyIDs(format) {
            do {
                _ = try await registry.evict(modelID)
            } catch is OnDeviceModelBusy {
                throw InstalledModelError.turnRunning
            } catch {
                throw InstalledModelError.removalFailed
            }
        }
    }
}
