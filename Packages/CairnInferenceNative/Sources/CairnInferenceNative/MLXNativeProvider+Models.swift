import CairnChatDomain
import Foundation

// The listing and switching half of the engine, kept out of `MLXNativeProvider.swift` so that file stays
// about the turn's memory lifecycle.
//
// Two rules hold this shape together:
//
// * **What is installed is what is offered.** The engine has no synthetic model row. Before this, it
//   reported one hard-coded entry however many folders the phone held, so three downloaded models looked
//   like one un-switchable model and the picker had nothing to choose.
// * **A switch moves the engine, not just the label.** Choosing a folder hands the previous one's weights
//   back through the ledger, which is the only path that knows whether a turn is mid-stream, so the phone
//   is never asked to hold two models at once and a running answer is never torn in half.
extension MLXNativeProvider {

    /// The folders on this phone this runtime can load, in the order the store reports them.
    func installedRecords() -> [ModelInfo] {
        installed().map { folder in
            ModelInfo(
                id: folder.id,
                displayName: folder.displayName,
                providerID: id,
                // The badge is the folder's own format, read from the files by the layer that looked at
                // them. Every row here is MLX today; saying it out loud is what stops a second on-device
                // runtime being added later from making these rows ambiguous.
                runtimeBadge: folder.format.badgeText
            )
        }
    }

    /// Points this engine at one of its own folders.
    ///
    /// - Throws: `NativeGenerationError.modelNotInstalled` when the id names no folder on this phone —
    ///   a model deleted while the chat sat open is the ordinary case for that, and a picker that quietly
    ///   accepted the choice would fail on the next turn instead of saying so now.
    public func selectModel(_ modelID: String) async throws {
        let wanted = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = installed().first(where: { $0.id == wanted }) else {
            throw NativeGenerationError.modelNotInstalled
        }
        // Asking for the model that is already live costs nothing. The session re-states its selection on
        // every model load, and a switch that released weights each time would be a reload per keystroke.
        guard match.id != activeModelID else { return }
        activeModelID = match.id
        // The weights that were held go back before the next turn asks for the new folder's. The release
        // is asked through the ledger rather than taken directly: a turn in flight keeps its model until
        // it ends, and the folder change lands on the turn after. Either way the runtime's buffer cache is
        // cleared, which is the half that actually returns memory to iOS.
        await ledger.requestRelease()
        let holding = await pool.isLoaded
        if !holding { loaded = nil }
    }

    /// The folder one turn loads, or nil when this phone holds nothing loadable.
    func turnDirectory(for request: GenerationRequest) -> URL? {
        NativeModelChoice.resolve(
            installed: installed(),
            requestedID: request.modelID,
            activeID: activeModelID
        )?.directoryURL
    }

    /// The folder this engine would load right now, for the memory gate and the Servers row.
    public func activeDirectory() -> URL? {
        NativeModelChoice.resolve(
            installed: installed(),
            requestedID: nil,
            activeID: activeModelID
        )?.directoryURL
    }
}
