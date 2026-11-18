import Foundation

/// What one attached file contributes to a `.cairn` file: its description, never its bytes.
///
/// That distinction is the whole reason this type exists instead of reusing `ChatAttachment`, which carries
/// `payload`. A `.cairn` file is JSON on purpose: a user can open it in a text editor, diff two exports by
/// hand, and AirDrop one to a friend. Turning a photograph into a base64 blob inside it would make the file
/// unreadable, grow it by the size of every photo the conversation ever held, and move those photographs to
/// wherever the user happened to send the file — a decision that has to be made per file, never as a
/// side effect of "export the chat".
///
/// So an export carries the **story** of an attachment: which file, of what kind, how big, and — for a
/// document — the text Cairn read out of it on this device, which is what a source line points back into.
/// Embedding the bytes is a separate, opt-in feature this build does not have.
public struct ExportedAttachment: Sendable, Equatable, Codable {
    public var id: UUID
    public var kind: String
    public var name: String
    public var declaredType: String
    public var byteCount: Int
    /// The text Cairn read from this document here on the device. It is carried because it is the text the
    /// answer was grounded in, and a reader of the file cannot check a citation without it.
    public var text: String?

    public init(_ attachment: ChatAttachment) {
        id = attachment.id
        kind = attachment.kind.rawValue
        name = attachment.name
        declaredType = attachment.declaredType
        byteCount = attachment.byteCount
        text = attachment.text
    }

    /// The attachment as the app reads it back: metadata, and no bytes, because no bytes were in the file.
    /// `ChatSessionModel.attachmentPayload` then answers nil, which is the honest state — this phone holds
    /// the description of a file it does not have.
    ///
    /// nil when the kind is not one this build has. Never a guess into the nearest kind: the two kinds
    /// differ in a privacy question, and reading an image as a document would put pixels somewhere a
    /// document would not go.
    public func toAttachment() -> ChatAttachment? {
        guard let readKind = AttachmentKind(rawValue: kind) else { return nil }
        return ChatAttachment(
            id: id,
            kind: readKind,
            name: name,
            declaredType: declaredType,
            byteCount: byteCount,
            payload: Data(),
            text: text
        )
    }

    /// True when this carries bytes, which it never does. Named so a test can assert the absence rather than
    /// reading the JSON and hoping it noticed.
    public var carriesBytes: Bool { false }
}

/// The attachments of one exported message, in the order a row and a transcript both use.
public enum ExportedAttachments {
    /// nil for a message that carried nothing, so a pre-M6 export and an M6 export of an empty message
    /// write the same bytes rather than one adding an empty array.
    public static func export(_ attachments: [ChatAttachment]) -> [ExportedAttachment]? {
        guard !attachments.isEmpty else { return nil }
        return Attachments.sorted(attachments).map(ExportedAttachment.init)
    }
}
