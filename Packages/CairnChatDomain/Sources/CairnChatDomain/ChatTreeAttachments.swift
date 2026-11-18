import Foundation

/// Attachments on their way to a provider.
///
/// Two rules, both of them about what the user can check afterwards:
///
/// - **An image rides on the turn it was attached to, and on no other turn.** Re-sending a photo with
///   every later message multiplies the bytes of a conversation on every turn for a benefit the user
///   cannot see, and a model given a photo it was not asked about will talk about it.
/// - **A document never travels as an attachment.** It was read on this device; only the passages that
///   answer the question go onward, inside the one system block.
extension ChatTree {
    /// The images attached to the newest user turn on the path, in display order.
    ///
    /// These are the attachments, not their bytes: a node read back from disk carries metadata and leaves
    /// the pixels in a file, so only the layer that owns that file can turn these into what goes on the
    /// wire. `ChatSessionModel.imagePayloads(for:)` does exactly that.
    public static func currentTurnImages(in path: [ChatNode]) -> [ChatAttachment] {
        guard let node = path.last(where: { $0.role == .user }) else { return [] }
        return Attachments.images(Attachments.sorted(node.attachments))
    }

    /// Puts those bytes on the payload the model reads images from: the last real user payload. A tool
    /// result also travels with the user role, so it is named out and skipped — images belong to what the
    /// user typed, not to what a tool handed back.
    public static func attaching(
        _ images: [Data], toLastUserOf messages: [ChatMessagePayload]
    ) -> [ChatMessagePayload] {
        guard !images.isEmpty else { return messages }
        guard let index = messages.lastIndex(where: {
            $0.role == .user && !$0.isToolResult
        }) else { return messages }
        var updated = messages
        updated[index].imageData = images
        return updated
    }

    /// True when a path has anything attached at all — the fact a transcript or a badge reads.
    public static func hasAttachments(in path: [ChatNode]) -> Bool {
        path.contains { !$0.attachments.isEmpty }
    }

    /// Every document attached anywhere on the path, in the order the conversation meets them.
    public static func documents(in path: [ChatNode]) -> [ChatAttachment] {
        path.flatMap { Attachments.documents($0.attachments) }
    }

    /// Every image attached anywhere on the path — the list a transcript exports, not the list a turn
    /// sends, which is `currentTurnImages`.
    public static func images(in path: [ChatNode]) -> [ChatAttachment] {
        path.flatMap { Attachments.images($0.attachments) }
    }
}
