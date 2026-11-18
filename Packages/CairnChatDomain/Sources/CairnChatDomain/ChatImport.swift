import Foundation

/// The part of opening a `.cairn` file that needs no store and no simulator: read the file's values, and
/// refuse what this build cannot represent.
///
/// Every refusal names the shape that failed rather than a fragment of the content, because the error is
/// shown in the UI and may be quoted by the user in a bug report. Nothing here guesses: an unknown mode,
/// role, kind or state is a **no**, because decoding a message into the nearest known value would put
/// words in a model's mouth and, for a mode, could send a prompt somewhere the user never chose.
public enum ChatImport {

    /// A file's chats and messages, checked, with their own ids still intact.
    public struct Contents: Sendable, Equatable {
        public var conversations: [Conversation]
        public var nodes: [ChatNode]
    }

    public static func contents(_ bundle: ChatExportBundle) throws -> Contents {
        var chats: [Conversation] = []
        for chat in bundle.chats {
            guard let conversation = chat.toConversation() else {
                throw ChatExportIssue.malformed("a chat asks for the mode “\(chat.mode)”, which this build does not have")
            }
            chats.append(conversation)
        }

        var nodes: [ChatNode] = []
        var seen: Set<UUID> = []
        for exported in bundle.nodes {
            guard let node = exported.toNode() else {
                throw ChatExportIssue.malformed("a message uses a role, kind or state this build does not have")
            }
            guard !seen.contains(node.id) else {
                throw ChatExportIssue.malformed("two messages carry the same id")
            }
            seen.insert(node.id)
            nodes.append(node)
        }

        let chatIDs = Set(chats.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            guard chatIDs.contains(node.conversationID) else {
                throw ChatExportIssue.malformed("a message belongs to a chat that is not in the file")
            }
            if let parent = node.parentID {
                guard let parentEntry = byID[parent] else {
                    throw ChatExportIssue.malformed("a message points at a parent that is not in the file")
                }
                guard parentEntry.conversationID == node.conversationID else {
                    throw ChatExportIssue.malformed("a message's parent belongs to a different chat")
                }
            }
        }
        for conversation in chats {
            guard let leaf = conversation.activeLeafID else { continue }
            guard byID[leaf]?.conversationID == conversation.id else {
                throw ChatExportIssue.malformed("a chat is open at a message that is not part of it")
            }
        }
        try rejectCycles(nodes, byID: byID)
        return Contents(conversations: chats, nodes: nodes)
    }

    /// Walking up from every message must end at a root. A file with a cycle would hang the tree walk
    /// that builds a transcript, so it is refused at the door rather than defended against later.
    static func rejectCycles(_ nodes: [ChatNode], byID: [UUID: ChatNode]) throws {
        for node in nodes {
            var visited: Set<UUID> = [node.id]
            var cursor = node.parentID
            while let parent = cursor {
                if visited.contains(parent) {
                    throw ChatExportIssue.malformed("a message is its own ancestor")
                }
                visited.insert(parent)
                cursor = byID[parent]?.parentID
            }
        }
    }

    /// Roots before their children, preserving the file's own order within one depth. SwiftData has no
    /// foreign key to satisfy, but writing a parent before its child keeps a half-written import readable
    /// as a tree instead of a set of orphans.
    static func sortedParentFirst(_ nodes: [ChatNode]) -> [ChatNode] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var depths: [UUID: Int] = [:]
        func depth(of id: UUID) -> Int {
            if let known = depths[id] { return known }
            guard let parent = byID[id]?.parentID, byID[parent] != nil else {
                depths[id] = 0
                return 0
            }
            let value = depth(of: parent) + 1
            depths[id] = value
            return value
        }
        return nodes.enumerated()
            .sorted { lhs, rhs in
                let left = depth(of: lhs.element.id)
                let right = depth(of: rhs.element.id)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}
