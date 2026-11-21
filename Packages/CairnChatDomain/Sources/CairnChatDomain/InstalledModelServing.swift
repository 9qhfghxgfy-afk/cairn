import Foundation

/// The seam behind the Installed section's device-owned half.
///
/// `CairnAppUI` may look at neither a filesystem nor a runtime, so the two things the Installed section
/// needs to know about this phone — what folders exist and what iOS makes available — arrive as entries
/// from the App layer. The same object is asked to take a model back, because the order that removal has
/// to run in (release the resident model, then remove the bytes) involves the registry and the unload
/// sink, and neither may be reached from a view model.
///
/// One removal path rather than two on purpose: the Download tab's detail sheet and the Installed list's
/// row both come through here, so "what does deleting a model mean" has exactly one answer.
@MainActor
public protocol InstalledModelServing: Sendable {
    /// What this phone holds and what iOS makes available, in the store's order.
    ///
    /// Remote servers are not asked here — they are already read by `RemoteModelManaging`, and a second
    /// reader of the same list is a second thing to keep honest.
    func installedEntries() async throws -> [InstalledModelEntry]

    /// Takes one model back: unloads it if it is resident, then removes its files.
    ///
    /// Throws `InstalledModelError.turnRunning` rather than deleting under an active turn, and
    /// `InstalledModelError.systemManaged` for a model iOS owns. A removal that half-succeeds is reported
    /// as a failure rather than as a success with an apology: the row has to stay where it is.
    func remove(_ entry: InstalledModelEntry) async throws
}
