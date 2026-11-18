import Foundation
import CairnChatDomain

/// The bytes of the files a conversation carries, kept beside the database rather than inside it.
///
/// The reason is a cost the user would feel: opening a chat reads every message row in it, so a photograph
/// stored in a row would be read whole on every open, and a conversation of forty photos would turn into a
/// long wait to see text. Here the row carries what a chip needs — name, kind, size — and the pixels are
/// read only for the two things that actually need them: drawing one thumbnail, and sending one turn.
///
/// A file is named by the attachment's own UUID. The user's file name is kept in the row, not in the path:
/// two attachments called `notes.txt` are two files, and a path built from a name would say where on this
/// phone the original lived, which is a fact about the device and not about the conversation.
///
/// This is a directory inside the app's own Application Support — not an iCloud-synced container, not
/// shared, not a group container another app can read. Nothing here reaches a network.
public struct AttachmentFiles {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    /// The app's own attachment directory, or nil when this device will not give one out — in which case
    /// attachments stay in memory for the session and the app says so rather than pretending to store them.
    public static func inApplicationSupport() -> AttachmentFiles? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return AttachmentFiles(directory: base.appendingPathComponent("Cairn/Attachments", isDirectory: true))
    }

    public func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString)
    }

    /// Writes the bytes of attachments that are not already stored. Idempotent, because the row a streaming
    /// turn updates is written several times and a photo must not be rewritten on every chunk.
    public func store(_ attachments: [ChatAttachment]) throws {
        for attachment in attachments where !attachment.payload.isEmpty {
            let destination = url(for: attachment.id)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            do {
                try attachment.payload.write(to: destination, options: .atomic)
            } catch {
                // The id and the size are typed metadata; the bytes themselves are never named or logged.
                throw StoreError.writeFailed(
                    "Could not store the attachment \(attachment.id.uuidString.prefix(8)) "
                        + "(\(attachment.byteCount) bytes)."
                )
            }
        }
    }

    public func data(for id: UUID) -> Data? {
        try? Data(contentsOf: url(for: id))
    }

    public func contains(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    /// Removes the files of deleted messages. Deleting a conversation without this would leave a copy of
    /// every photo the user deleted sitting on the phone, which is the opposite of what delete means here.
    public func remove(ids: [UUID]) {
        for id in ids {
            try? FileManager.default.removeItem(at: url(for: id))
        }
    }
}
