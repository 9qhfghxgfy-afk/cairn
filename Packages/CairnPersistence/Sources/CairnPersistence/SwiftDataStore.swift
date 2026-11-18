import Foundation
import SwiftData
import CairnChatDomain

/// SwiftData-backed store. The only module in the app allowed to touch SwiftData.
///
/// Node identity is a parent pointer + branch index, so a write is either an insert
/// of a new row or an in-place update of one row. Nothing is ever rewritten in bulk,
/// which is what keeps edit / regenerate / branch cheap and non-destructive.
@MainActor
public final class SwiftDataStore: ChatStore {
    private let container: ModelContainer
    /// Internal, not private: `SwiftDataStore+Profiles.swift` extends this type in another
    /// file and needs the same single writer.
    let context: ModelContext
    /// The files the attachments in these rows point at, or nil for an in-memory store — which writes
    /// nothing at all, including no photographs. Internal for the same reason as `context`: the attachment
    /// extension of this type is in another file and needs the same single place files are written.
    let attachmentFiles: AttachmentFiles?

    /// - Parameter inMemory: used by tests and by any "do not write to disk" path. An in-memory store has
    ///   no directory to write to, so it keeps no attachment file either; a disk store that cannot get one
    ///   keeps the conversation working in memory and says so at the composer rather than failing to open.
    public convenience init(inMemory: Bool = false) throws {
        try self.init(
            inMemory: inMemory,
            attachments: inMemory ? nil : AttachmentFiles.inApplicationSupport()
        )
    }

    /// The full form: which database, and which directory the attachment files live in.
    ///
    /// The second argument exists so the file side of persistence can be tested at all. The default form
    /// gives an in-memory database no directory, which is the right behaviour on a phone and a useless one
    /// in a test that has to prove a photograph is written **before** the row that names it, and removed
    /// with the message that owned it. An in-memory database plus a throwaway directory says exactly that.
    public init(inMemory: Bool = false, attachments: AttachmentFiles?) throws {
        do {
            if inMemory {
                container = try ModelContainer(
                    for: ConversationRecord.self, ChatRecord.self, ServerProfileRecord.self,
                    ServerSelectionRecord.self, SettingsRecord.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } else {
                container = try ModelContainer(
                    for: ConversationRecord.self, ChatRecord.self, ServerProfileRecord.self,
                    ServerSelectionRecord.self, SettingsRecord.self
                )
            }
        } catch {
            throw StoreError.writeFailed("Could not open the local chat database.")
        }
        // The caller decides where the bytes live — which is nothing at all for an in-memory store, and a
        // throwaway directory for the test that watches a file being written and deleted.
        attachmentFiles = attachments
        // Main-actor bound context matches this store's isolation, and keeps the
        // app and the store on one writer instead of juggling several contexts.
        context = container.mainContext
    }

    // MARK: - Where the other halves live

    /// Reading a stored file and cleaning up after a delete live in `SwiftDataStore+Attachments.swift`;
    /// conversation rows live in `SwiftDataStore+Conversations.swift`; profiles, settings and the server
    /// selection each have their own extension. What is left here is the shape of the store itself: the
    /// container, one writer, and the one node row a stream updates in place.

    // MARK: - Nodes

    public func nodes(conversationID: UUID) throws -> [ChatNode] {
        let descriptor = FetchDescriptor<ChatRecord>(
            predicate: #Predicate { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map { $0.toNode() }
    }

    public func saveNode(_ node: ChatNode) throws {
        // Bytes first, row second: a row that names a file which was never written is a message whose image
        // silently disappeared, so a failure to store the file fails the save instead.
        try attachmentFiles?.store(node.attachments)
        let nodeID = node.id
        var descriptor = FetchDescriptor<ChatRecord>(predicate: #Predicate { $0.id == nodeID })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            // Streaming updates land here: one row, in place, no array rewrite.
            existing.text = node.text
            existing.thinking = node.thinking
            existing.stateRaw = node.state.rawValue
            // A synthesized turn hands its node's text to the engine that wrote it, so attribution
            // is updated with the text. Leaving the first candidate's id here would credit the
            // wrong engine for the answer standing on the node.
            existing.providerID = node.providerID
            existing.modelID = node.modelID
            existing.draftsJSON = JSONCodec.encodeIfNotEmpty(node.drafts)
            existing.metricsJSON = node.metrics.flatMap { JSONCodec.encode($0) }
            existing.provenanceJSON = node.provenance.flatMap { JSONCodec.encode($0) }
            // Sources arrive when a grounded answer finishes, which is after the row was first written with
            // an empty text — so the citation column has to be written on the update path too, or the
            // answer's sources would never be stored.
            existing.citationsJSON = JSONCodec.encodeIfNotEmpty(node.citations)
        } else {
            context.insert(ChatRecord(node))
        }
        try context.save()
    }

    public func deleteNode(id: UUID) throws {
        var descriptor = FetchDescriptor<ChatRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw StoreError.nodeNotFound(id)
        }
        let attachmentIDs = AttachmentMetadataCodec.ids(in: record.attachmentsJSON)
        context.delete(record)
        try context.save()
        // The row goes first so a delete that fails leaves the file, not the row pointing at a file that is
        // already gone.
        attachmentFiles?.remove(ids: attachmentIDs)
    }
}
