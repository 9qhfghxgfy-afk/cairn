import Foundation
import CairnChatDomain

/// The file side of an attachment: reading a stored file back, and removing files when the message that
/// owned them goes away.
///
/// Kept apart from the store's own file because the two jobs are different. The store's file is about rows —
/// one insert or one in-place update, which is what makes the tree cheap. This file is about the bytes beside
/// those rows, which is the part of persistence that can fail for reasons the database has nothing to do
/// with: a full disk, a file the user deleted in the Files app, a container iOS decided to sweep.
extension SwiftDataStore {
    /// The stored file behind an attachment, or nil when it was never written or has gone missing. The app
    /// hands this to `ChatSessionModel.attachmentBytes`, which is the only reader of attachment files in the
    /// app: a view that wants a thumbnail asks the session, the session asks here, and nothing reads a
    /// photograph off disk to build a transcript.
    public func attachmentData(id: UUID) -> Data? {
        attachmentFiles?.data(for: id)
    }

    /// Whether this store can keep an attached file between turns. It cannot when it is in-memory — a photo
    /// in that conversation exists only as long as the app is open, which the composer says out loud rather
    /// than letting the user believe a picture had been saved — and it cannot when the directory it was given
    /// is not a directory it can write. The second case is the one worth stating early: a store that reports
    /// itself able and then fails at send time leaves the user holding a failed send and a photo they cannot
    /// find out of, so the flag asks the directory what it is instead of trusting that it was created.
    public var canStoreAttachments: Bool {
        attachmentFiles?.isWritable ?? false
    }

    /// Drops the files belonging to a set of message rows, which is what makes deleting a message actually
    /// delete what it carried.
    func removeAttachmentFiles(from records: [ChatRecord]) {
        let ids = records.flatMap { AttachmentMetadataCodec.ids(in: $0.attachmentsJSON) }
        guard !ids.isEmpty else { return }
        attachmentFiles?.remove(ids: ids)
    }
}
