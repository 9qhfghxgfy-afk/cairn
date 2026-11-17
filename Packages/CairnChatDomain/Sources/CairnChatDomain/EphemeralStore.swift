import Foundation

/// Memory-only store backing Temporary Chat. Nothing here is ever written to disk,
/// and the whole structure dies with the process — which is exactly what the user
/// asked for when they toggle temporary chat on.
@MainActor
public final class EphemeralStore: ChatStore {
    private var conversations: [UUID: Conversation] = [:]
    private var nodes: [UUID: ChatNode] = [:]

    public init() {}

    public func loadConversations() throws -> [Conversation] {
        conversations.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func createConversation(
        title: String,
        mode: InferenceMode,
        config: ChatConfig,
        isTemporary: Bool
    ) throws -> Conversation {
        let conversation = Conversation(
            title: title,
            mode: mode,
            config: config,
            isTemporary: isTemporary
        )
        conversations[conversation.id] = conversation
        return conversation
    }

    public func conversation(id: UUID) throws -> Conversation? {
        conversations[id]
    }

    public func saveConversation(_ conversation: Conversation) throws {
        conversations[conversation.id] = conversation
    }

    public func deleteConversation(id: UUID) throws {
        conversations.removeValue(forKey: id)
        for node in nodes.values where node.conversationID == id {
            nodes.removeValue(forKey: node.id)
        }
    }

    public func nodes(conversationID: UUID) throws -> [ChatNode] {
        nodes.values.filter { $0.conversationID == conversationID }
    }

    public func saveNode(_ node: ChatNode) throws {
        nodes[node.id] = node
    }

    public func deleteNode(id: UUID) throws {
        nodes.removeValue(forKey: id)
    }
}
