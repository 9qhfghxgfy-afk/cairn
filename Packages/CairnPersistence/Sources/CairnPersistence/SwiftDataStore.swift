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

    /// - Parameter inMemory: used by tests and by any "do not write to disk" path.
    public init(inMemory: Bool = false) throws {
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
        // An in-memory store has no directory to write to; a disk store that cannot get one keeps the
        // conversation working in memory and says so at the composer rather than failing to open.
        attachmentFiles = inMemory ? nil : AttachmentFiles.inApplicationSupport()
        // Main-actor bound context matches this store's isolation, and keeps the
        // app and the store on one writer instead of juggling several contexts.
        context = container.mainContext
    }

    // MARK: - Attachment bytes

    /// Reading a stored file and cleaning up after a delete live in `SwiftDataStore+Attachments.swift`, so
    /// this file stays the shape of the store: conversations, nodes, one writer.

    // MARK: - Conversations

    public func loadConversations() throws -> [Conversation] {
        let descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toConversation() }
    }

    public func createConversation(
        title: String,
        mode: InferenceMode,
        config: ChatConfig,
        isTemporary: Bool
    ) throws -> Conversation {
        // Defence in depth: temporary chat must be handled by EphemeralStore.
        guard !isTemporary else {
            throw StoreError.writeFailed("Temporary chats are never written to disk.")
        }
        let conversation = Conversation(title: title, mode: mode, config: config, isTemporary: false)
        try saveConversation(conversation)
        return conversation
    }

    public func conversation(id: UUID) throws -> Conversation? {
        var descriptor = FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.toConversation()
    }

    public func saveConversation(_ conversation: Conversation) throws {
        guard !conversation.isTemporary else {
            throw StoreError.writeFailed("Temporary chats are never written to disk.")
        }
        // Hoist captures: `#Predicate` is happiest with plain locals.
        let conversationID = conversation.id
        var descriptor = FetchDescriptor<ConversationRecord>(
            predicate: #Predicate { $0.id == conversationID }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.title = conversation.title
            existing.activeLeafID = conversation.activeLeafID
            existing.updatedAt = conversation.updatedAt
            existing.modeRaw = conversation.mode.rawValue
            existing.configJSON = JSONCodec.encode(conversation.config)
        } else {
            context.insert(ConversationRecord(conversation))
        }
        try context.save()
    }

    public func deleteConversation(id: UUID) throws {
        var conversationDescriptor = FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.id == id })
        conversationDescriptor.fetchLimit = 1
        guard let record = try context.fetch(conversationDescriptor).first else {
            throw StoreError.conversationNotFound(id)
        }
        let nodeDescriptor = FetchDescriptor<ChatRecord>(predicate: #Predicate { $0.conversationID == id })
        let nodeRecords = try context.fetch(nodeDescriptor)
        for node in nodeRecords {
            context.delete(node)
        }
        context.delete(record)
        try context.save()
        // And the files with them. A deleted conversation that left its photographs behind is not a deleted
        // conversation; it is a conversation the user cannot see but whose contents still sit on the phone.
        removeAttachmentFiles(from: nodeRecords)
    }

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
