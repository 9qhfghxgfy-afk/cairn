import Foundation
import CairnChatDomain

/// The row's description of one attached file: what it is, how big it is, and the text Cairn read out of
/// it here on the device. Never its bytes.
///
/// Those two sentences are the whole design. A transcript is opened by reading every node row in the
/// conversation, so a photograph kept in the row would be read whole on every open — and a conversation of
/// forty photos would make opening it take a long time for pictures the screen never shows. The pixels sit
/// in a file beside the database, named by the attachment's own id; this is what the row needs to draw a
/// chip and to search a document on a later turn.
///
/// The document's text is the one part of its contents that is stored. It is stored because retrieval has
/// to be able to search a file attached three turns ago without touching a disk, and because storing it is
/// what makes an export show what was actually searched rather than what the file might have said.
struct AttachmentMetadata: Codable {
    var id: UUID
    var kindRaw: String
    var name: String
    var declaredType: String
    var byteCount: Int
    var text: String?

    init(_ attachment: ChatAttachment) {
        id = attachment.id
        kindRaw = attachment.kind.rawValue
        name = attachment.name
        declaredType = attachment.declaredType
        byteCount = attachment.byteCount
        text = attachment.text
    }

    func toAttachment() -> ChatAttachment {
        ChatAttachment(
            id: id,
            kind: AttachmentKind(rawValue: kindRaw) ?? .document,
            name: name,
            declaredType: declaredType,
            byteCount: byteCount,
            // Deliberately empty: the bytes belong to `AttachmentFiles`, and the session reads them back
            // only for a turn that is about to send them.
            payload: Data(),
            text: text
        )
    }
}

/// The one place attachment metadata is turned to and from JSON, so a row written by one version of the app
/// is readable by the next.
enum AttachmentMetadataCodec {
    static func encode(_ attachments: [ChatAttachment]) -> Data? {
        guard !attachments.isEmpty else { return nil }
        return JSONCodec.encode(attachments.map(AttachmentMetadata.init))
    }

    static func decode(_ data: Data?) -> [ChatAttachment] {
        guard let data,
              let stored = JSONCodec.decode([AttachmentMetadata].self, from: data) else { return [] }
        return stored.map { $0.toAttachment() }
    }

    /// The ids a row refers to, which is all `deleteNode` needs in order to remove the files with it.
    static func ids(in data: Data?) -> [UUID] {
        decode(data).map(\.id)
    }
}
