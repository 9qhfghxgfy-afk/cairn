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
        // Main-actor bound context matches this store's isolation, and keeps the
        // app and the store on one writer instead of juggling several contexts.
        context = container.mainContext
    }

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
        for node in try context.fetch(nodeDescriptor) {
            context.delete(node)
        }
        context.delete(record)
        try context.save()
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
        let nodeID = node.id
        var descriptor = FetchDescriptor<ChatRecord>(predicate: #Predicate { $0.id == nodeID })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            // Streaming updates land here: one row, in place, no array rewrite.
            existing.text = node.text
            existing.thinking = node.thinking
            existing.stateRaw = node.state.rawValue
            existing.modelID = node.modelID
            existing.draftsJSON = JSONCodec.encodeIfNotEmpty(node.drafts)
            existing.metricsJSON = node.metrics.flatMap { JSONCodec.encode($0) }
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
        context.delete(record)
        try context.save()
    }
}
