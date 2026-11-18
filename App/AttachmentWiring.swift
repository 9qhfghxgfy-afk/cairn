import CairnChatDomain
import CairnPersistence
import Foundation

/// Puts the file side of attachments onto a workspace, from the layer that is allowed to know both halves.
///
/// Two facts have to meet for an attachment to work, and they live in modules that may not know about each
/// other: the store that can read a stored file (SwiftData, and therefore `CairnPersistence`) and the session
/// that asks for those bytes when a turn is about to send them (`CairnChatDomain`). The domain must not open
/// a file; the UI must not import SwiftData. This file is where the app joins them, next to the Keychain, the
/// providers and the tools — the other things only the app layer is allowed to hold.
///
/// The reader travels to every session the workspace creates, and so does the answer to "can this device keep
/// the file at all". Both have to be set together: a session that can ask for bytes but was never told where
/// they come from would report an attachment as unreadable, and a session told the store can keep files when
/// it cannot would promise the user something that vanishes at relaunch.
@MainActor
public enum AttachmentWiring {
    /// Hands a workspace the store's reader and the store's honest answer about storage.
    ///
    /// Idempotent, and called again if a workspace is rebuilt: installing is assignment, not accumulation, so
    /// there is nothing to undo first.
    public static func install(on workspace: ChatWorkspace, store: SwiftDataStore) {
        workspace.attachmentReader = store.attachmentData
        workspace.attachmentStorageAvailable = store.canStoreAttachments
    }

    /// The reader and the flag as one value, for a workspace with no files behind it — a preview, a test, or
    /// a device whose store could not get a directory. A session built this way can still describe an
    /// attachment and still send it in the turn it was picked for; it simply cannot read a stored file back,
    /// which is what `attachmentStorageAvailable` tells the composer.
    public static func installNothing(on workspace: ChatWorkspace) {
        workspace.attachmentReader = nil
        workspace.attachmentStorageAvailable = false
    }
}
