import Foundation

/// What an import is going to write: the chats and messages, with their final ids already decided.
public struct ChatImportPlan: Sendable, Equatable {
    public var conversations: [Conversation]
    public var nodes: [ChatNode]
    /// True when the file's own ids were already taken in this store, so every chat and message was
    /// given a fresh one. The app shows this as "imported as a copy".
    public var assignedFreshIDs: Bool
    /// The new ids of chats whose title gained " (copy)" — the ones that duplicated an existing chat.
    public var copiedConversationIDs: Set<UUID>

    public init(
        conversations: [Conversation],
        nodes: [ChatNode],
        assignedFreshIDs: Bool,
        copiedConversationIDs: Set<UUID> = []
    ) {
        self.conversations = conversations
        self.nodes = nodes
        self.assignedFreshIDs = assignedFreshIDs
        self.copiedConversationIDs = copiedConversationIDs
    }
}

/// Turns a checked file into rows to write, and writes them.
///
/// An id collision means the file describes a chat this store already has. The answer is never to
/// overwrite: `saveNode` updates a row in place for streaming, so re-using an id would silently rewrite
/// someone's existing message with a stranger's text. Instead the whole file is imported as a copy with
/// new ids, parent pointers and leaf pointer remapped together so the tree is still intact. Re-importing
/// the same file twice therefore yields two chats, which is the honest outcome and the one the user can
/// undo by deleting one of them.
/// The planning half of `ChatImport`, kept apart from the checking half in `ChatImport.swift`. The
/// enum itself is declared there, so this file extends it rather than redeclaring it.
public extension ChatImport {

    static func plan(
        _ bundle: ChatExportBundle,
        takenConversationIDs: Set<UUID>,
        takenNodeIDs: Set<UUID>
    ) throws -> ChatImportPlan {
        let read = try contents(bundle)
        let collides = read.conversations.contains { takenConversationIDs.contains($0.id) }
            || read.nodes.contains { takenNodeIDs.contains($0.id) }
        guard collides else {
            return ChatImportPlan(
                conversations: read.conversations,
                nodes: sortedParentFirst(read.nodes),
                assignedFreshIDs: false
            )
        }

        var chatMap: [UUID: UUID] = [:]
        for conversation in read.conversations { chatMap[conversation.id] = UUID() }
        var nodeMap: [UUID: UUID] = [:]
        for node in read.nodes { nodeMap[node.id] = UUID() }

        var copied: Set<UUID> = []
        let conversations = read.conversations.map { chat -> Conversation in
            var opened = chat
            opened.id = chatMap[chat.id] ?? UUID()
            opened.activeLeafID = chat.activeLeafID.flatMap { nodeMap[$0] }
            if takenConversationIDs.contains(chat.id) {
                opened.title = "\(chat.title) (copy)"
                copied.insert(opened.id)
            }
            return opened
        }
        let nodes = read.nodes.map { node -> ChatNode in
            var opened = node
            opened.id = nodeMap[node.id] ?? UUID()
            opened.conversationID = chatMap[node.conversationID] ?? node.conversationID
            opened.parentID = node.parentID.flatMap { nodeMap[$0] }
            return opened
        }
        return ChatImportPlan(
            conversations: conversations,
            nodes: sortedParentFirst(nodes),
            assignedFreshIDs: true,
            copiedConversationIDs: copied
        )
    }

    /// Writes a file into a store. Existing chats are read first only to learn which ids are taken.
    @MainActor
    static func apply(_ bundle: ChatExportBundle, to store: any ChatStore) throws -> ChatImportPlan {
        let existing = try store.loadConversations()
        var takenNodeIDs: Set<UUID> = []
        for conversation in existing {
            for node in try store.nodes(conversationID: conversation.id) { takenNodeIDs.insert(node.id) }
        }
        let opened = try plan(
            bundle,
            takenConversationIDs: Set(existing.map(\.id)),
            takenNodeIDs: takenNodeIDs
        )
        for conversation in opened.conversations { try store.saveConversation(conversation) }
        for node in opened.nodes { try store.saveNode(node) }
        return opened
    }
}
