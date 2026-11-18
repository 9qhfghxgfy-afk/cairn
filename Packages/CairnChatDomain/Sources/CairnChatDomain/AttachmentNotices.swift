import Foundation

/// The sentence that says where an attached file actually lives.
///
/// An attachment is the one thing in this app a user can mistake for something that was saved: a photo
/// appears in the message, so it looks kept. In a temporary chat it is not — the chat lives in
/// `EphemeralStore`, and the file goes when the process does. On a device that will not hand out a
/// directory it is not kept either, for a different reason. Both cases get said in the composer, next to
/// the paperclip, rather than discovered later.
///
/// Nothing here blocks a send. A file the app cannot keep still rides the turn it was picked for; the
/// notice only refuses to promise what the app cannot deliver.
public enum AttachmentNotices {
    /// Temporary chat: the file is memory-only and dies with the process, which is the promise the chat
    /// makes for everything in it.
    public static let temporaryChatNotice =
        "This is a temporary chat, so an attached file is held in memory only. It goes when the app "
        + "closes — keep a copy of the answer if the file's contents matter."

    /// The store cannot write a file: an in-memory store, or a device that refused a directory.
    public static let storageUnavailableNotice =
        "Cairn cannot get a place on this device to keep attached files, so an attachment lives in memory "
        + "for this session only. It still travels with the turn you send; it is not there next time."

    /// The line to show, or nil when the app really can keep the file and has nothing to warn about.
    ///
    /// The temporary case wins: a temporary chat would not keep the file even if the store could, and
    /// naming the reason that applies first is more useful than naming the secondary one.
    public static func notice(temporaryChat: Bool, storageAvailable: Bool) -> String? {
        if temporaryChat { return temporaryChatNotice }
        if !storageAvailable { return storageUnavailableNotice }
        return nil
    }
}
