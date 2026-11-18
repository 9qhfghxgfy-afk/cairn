import Foundation

/// What the chat list shows and in what order.
///
/// Search is over the chat's title, not its messages. The list is built from conversation rows, and
/// reading every message of every chat to search inside it would make opening the drawer cost a full
/// table read on a phone whose data is all local; a title the user chose is what they search for. This
/// is stated here so the ledger row does not read as full-text search.
public enum ChatListQuery {

    /// The fallback a chat with an empty title is listed under.
    public static let untitledTitle = "Untitled chat"

    public static func visibleTitle(_ chat: Conversation) -> String {
        let title = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? untitledTitle : title
    }

    /// Case-insensitive title match. An empty query is everything, because an empty field means the
    /// user is browsing, not filtering.
    public static func matches(_ chat: Conversation, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return visibleTitle(chat).localizedCaseInsensitiveContains(needle)
    }

    public static func filter(_ chats: [Conversation], query: String) -> [Conversation] {
        chats.filter { matches($0, query: query) }
    }

    /// Most recently touched first — the order a list of chats has to be in, because the one the user
    /// was just in is the one they are looking for.
    public static func mostRecentFirst(_ chats: [Conversation]) -> [Conversation] {
        chats.sorted { lhs, rhs in
            lhs.updatedAt == rhs.updatedAt ? lhs.createdAt > rhs.createdAt : lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Search then sort, which is the whole job of the drawer's list.
    public static func list(_ chats: [Conversation], query: String = "") -> [Conversation] {
        mostRecentFirst(filter(chats, query: query))
    }
}
