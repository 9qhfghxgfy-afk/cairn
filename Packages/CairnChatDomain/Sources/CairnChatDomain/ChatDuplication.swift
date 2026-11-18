import Foundation

/// Copying a chat: the whole tree, or only the branch the chat is open on.
///
/// A copy always gets new ids. Re-using the file's or the chat's own ids would put the copy and the
/// original on the same rows — `saveNode` updates in place so the two chats would overwrite each other's
/// messages — so every id, parent pointer and leaf pointer is remapped together and the tree shape is
/// the only thing carried over.
///
/// "Duplicate up to the current branch" is the product rule: the user is looking at one path, and a copy
/// of a chat they branched three times should not silently carry the branches they walked away from. The
/// full-tree copy exists for the other job — keeping a temporary chat, where dropping anything the user
/// wrote would be a loss.
public enum ChatDuplication {

    /// The copy, ready to write: one chat and its messages, parents before children.
    public struct Copy: Sendable, Equatable {
        public var conversation: Conversation
        public var nodes: [ChatNode]

        public init(conversation: Conversation, nodes: [ChatNode]) {
            self.conversation = conversation
            self.nodes = nodes
        }
    }

    /// Every branch of the chat. Used by "keep a copy" — nothing the user wrote may be missing.
    public static func entireChat(
        _ chat: Conversation,
        nodes: [ChatNode],
        title: String? = nil,
        now: Date = Date()
    ) -> Copy {
        let own = nodes.filter { $0.conversationID == chat.id }
        return remap(chat, selected: own, title: title ?? "\(chat.title) (copy)", now: now)
    }

    /// Only the path the chat is open at, which is what a duplicate of the chat in front of the user means.
    public static func upToCurrentBranch(
        _ chat: Conversation,
        nodes: [ChatNode],
        title: String? = nil,
        now: Date = Date()
    ) -> Copy {
        let own = nodes.filter { $0.conversationID == chat.id }
        let path = ChatTree.visiblePath(nodes: own, activeLeafID: chat.activeLeafID)
        // A chat with no leaf pointer still has messages worth keeping; the fallback is the whole tree
        // rather than an empty chat, because losing text is the worse failure.
        let selected = path.isEmpty ? own : path
        return remap(chat, selected: selected, title: title ?? "\(chat.title) (copy)", now: now)
    }

    /// Fresh ids for a chosen set of messages, with parents and the leaf pointer moved with them.
    static func remap(
        _ chat: Conversation,
        selected: [ChatNode],
        title: String,
        now: Date
    ) -> Copy {
        let chatID = UUID()
        let kept = Set(selected.map(\.id))
        var nodeIDs: [UUID: UUID] = [:]
        for node in selected { nodeIDs[node.id] = UUID() }

        let copied = selected.map { node -> ChatNode in
            var moved = node
            moved.id = nodeIDs[node.id] ?? UUID()
            moved.conversationID = chatID
            // A parent that was not part of the copy stops being a parent: the copy's own first message
            // becomes the root instead of pointing into a tree the copy does not contain.
            moved.parentID = node.parentID.flatMap { kept.contains($0) ? nodeIDs[$0] : nil }
            return moved
        }

        var opened = Conversation(
            id: chatID,
            title: title,
            activeLeafID: chat.activeLeafID.flatMap { nodeIDs[$0] },
            createdAt: chat.createdAt,
            updatedAt: now,
            mode: chat.mode,
            config: chat.config,
            isTemporary: chat.isTemporary
        )
        // A chat copied from one that had no leaf pointer opens at the deepest message it kept, so the
        // duplicate is readable at once rather than open at nothing.
        if opened.activeLeafID == nil, let last = ChatImport.sortedParentFirst(copied).last {
            opened.activeLeafID = last.id
        }
        return Copy(conversation: opened, nodes: ChatImport.sortedParentFirst(copied))
    }
}
