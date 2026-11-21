import Foundation
import CairnChatDomain

/// What a removal from the Installed tab settles in the Download tab.
///
/// Both tabs read the same store, so a delete has to leave the other tab in agreement with it. Three facts
/// go stale together: the installed mark on the card, the transfer line still drawn under it, and the card
/// a sheet is open on. Left alone, a person who deletes a model and switches tabs watches a card that still
/// says "Installed" and still shows a finished progress bar for bytes that are gone.
extension ModelCatalogModel {
    /// Settles the list after one of this phone's models has been taken back.
    ///
    /// The status is cleared before the re-read rather than after: `refreshPartials` deliberately skips a row
    /// whose status says a transfer is in flight, and a stale in-flight line for a repository whose files no
    /// longer exist would keep the "being kept" answer from ever being asked again.
    ///
    /// A server pull is not touched. `pulledID` belongs to the Ollama path, and clearing it here would make
    /// the catalogue stop reporting a pull that is genuinely still running on someone else's machine.
    public func modelWasRemoved(repoID: String) async {
        if let status = phoneStatus, status.entryID == repoID { phoneStatus = nil }
        await refresh()
        repoint()
    }
}
