import Foundation
import SwiftData
import CairnChatDomain

/// Conversation rows: create one, read one, update one, delete one and its messages.
///
/// Kept apart from the store's own file so that file stays the shape of the store — the container, one
/// writer, and the node row a stream updates in place. A conversation is a single row either way: creating
/// one is an insert, saving one is an in-place update, and that is what lets the leaf pointer move on every
/// send without rewriting anything else in the database.
///
/// Temporary chats are refused here rather than filtered by the caller. They belong to `EphemeralStore`, so
/// a disk write marked temporary is a promise broken, and the refusal has to come from the thing that would
/// break it.
extension SwiftDataStore {
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
        // Hoisted capture: `#Predicate` is happiest with a plain local.
        let conversationID = id
        var descriptor = FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.id == conversationID })
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
        // Hoisted captures, for the same reason as every other predicate in this module.
        let conversationID = id
        var conversationDescriptor = FetchDescriptor<ConversationRecord>(
            predicate: #Predicate { $0.id == conversationID }
        )
        conversationDescriptor.fetchLimit = 1
        guard let record = try context.fetch(conversationDescriptor).first else {
            throw StoreError.conversationNotFound(id)
        }
        let nodeDescriptor = FetchDescriptor<ChatRecord>(
            predicate: #Predicate { $0.conversationID == conversationID }
        )
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
}
