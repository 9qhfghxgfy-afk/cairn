import Foundation

/// Getting an attachment's bytes back for the turn that is about to be sent.
///
/// The split is deliberate: a stored node carries an attachment's name, size and — for a document — the
/// text Cairn read from it, because retrieval has to be able to search a file attached three turns ago
/// without touching a disk. An image's pixels are not in the row. Loading a transcript must not read
/// every photograph a conversation ever held, so they sit in a file beside the database and come back only
/// for the turn that is actually about to send them.
///
/// What that buys is the failure this app is not allowed to have: if the bytes of an image a turn has to
/// send cannot be read, the turn is refused. Sending nothing where a photo was would produce an answer
/// about a picture that never arrived, with no sign anywhere that it went missing.
extension ChatSessionModel {
    /// One attachment's bytes: the ones the node carries if it carries them, otherwise the stored file.
    public func attachmentPayload(_ attachment: ChatAttachment) -> Data? {
        attachment.payload.isEmpty ? attachmentBytes?(attachment.id) : attachment.payload
    }

    /// The bytes to put on the wire for the images of the newest user message on a path.
    public func imagePayloads(in path: [ChatNode]) -> [Data] {
        ChatTree.currentTurnImages(in: path).compactMap(attachmentPayload)
    }

    /// True when every image this turn has to send can be read.
    ///
    /// Checked before a turn starts rather than during it, so a photo whose file has gone stops the turn
    /// with a message instead of arriving at the model as nothing.
    public func attachmentsReadable(in path: [ChatNode]) -> Bool {
        ChatTree.currentTurnImages(in: path).allSatisfy { attachmentPayload($0) != nil }
    }

    /// What the unreadable case says. Named here rather than in a view so the composer, a refused
    /// regenerate and a test all use one wording.
    public static let unreadableAttachmentMessage =
        "The file behind one of this message's images can no longer be read on this device, so it cannot "
        + "be sent again. Re-attach the image, or edit the message to send the text without it."
}
