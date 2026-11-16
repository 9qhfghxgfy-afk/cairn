import Foundation

public enum StoreError: Error, Equatable, Sendable, LocalizedError {
    case conversationNotFound(UUID)
    case nodeNotFound(UUID)
    case parentNotFound(UUID)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .conversationNotFound(let id): return "Conversation \(id.uuidString.prefix(8)) was not found."
        case .nodeNotFound(let id): return "Message \(id.uuidString.prefix(8)) was not found."
        case .parentNotFound: return "The parent of that message is missing."
        case .writeFailed(let reason): return "Could not save: \(reason)"
        }
    }
}

/// Storage boundary. All access is main-actor isolated on purpose: SwiftData's
/// `ModelContext` is not Sendable, and a chat tree has no reason to be mutated
/// from several threads at once.
///
/// `EphemeralStore` (memory only) and `SwiftDataStore` (disk) implement this, so
/// temporary chat mode is a store choice, not a flag scattered through the UI.
@MainActor
public protocol ChatStore: AnyObject {
    func loadConversations() throws -> [Conversation]
    func createConversation(
        title: String,
        mode: InferenceMode,
        params: SamplingParams,
        isTemporary: Bool
    ) throws -> Conversation
    func conversation(id: UUID) throws -> Conversation?
    func saveConversation(_ conversation: Conversation) throws
    func deleteConversation(id: UUID) throws

    func nodes(conversationID: UUID) throws -> [ChatNode]
    func saveNode(_ node: ChatNode) throws
    func deleteNode(id: UUID) throws
}
