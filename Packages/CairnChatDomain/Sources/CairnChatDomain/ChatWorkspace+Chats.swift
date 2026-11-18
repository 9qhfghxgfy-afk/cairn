import Foundation

/// The chat list and its actions: search, rename, duplicate, and keeping a copy of a temporary chat.
///
/// Every one of these goes through the store, because the store is the truth about a chat. The
/// `conversations` array is a display snapshot, and acting on it would act on stale data — the same trap
/// `select(conversationID:)` already documents for the leaf pointer.
///
/// Nothing here caps the list. A chat is a row the user made, and Cairn has no reason to make them
/// delete one to add another.
extension ChatWorkspace {

    /// The chats to list: filtered by title, most recently touched first.
    public func chats(matching query: String = "") -> [Conversation] {
        ChatListQuery.list(conversations, query: query)
    }

    /// Renames a chat, leaving `updatedAt` alone.
    ///
    /// A rename is not a visit. Bumping `updatedAt` would slide a chat the user last used a week ago to
    /// the top of a list sorted by recency, which reads as though something happened in it.
    public func rename(conversationID: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            guard var chat = try persistentStore.conversation(id: conversationID) else {
                lastError = StoreError.conversationNotFound(conversationID).errorDescription
                return
            }
            chat.title = trimmed
            try persistentStore.saveConversation(chat)
            if session?.conversation.id == conversationID { session?.conversation = chat }
            reloadConversations()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Copies the chat up to the branch it is open on, and returns the copy.
    public func duplicate(conversationID: UUID) -> Conversation? {
        do {
            guard let chat = try persistentStore.conversation(id: conversationID) else {
                lastError = StoreError.conversationNotFound(conversationID).errorDescription
                return nil
            }
            let copy = ChatDuplication.upToCurrentBranch(
                chat,
                nodes: try persistentStore.nodes(conversationID: conversationID)
            )
            try persistentStore.saveConversation(copy.conversation)
            for node in copy.nodes { try persistentStore.saveNode(node) }
            reloadConversations()
            return copy.conversation
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Writes a copy of the temporary chat to disk and **leaves the temporary chat open**.
    ///
    /// Flipping out of temporary mode instead would move the user out of the chat they are in and start a
    /// new empty one, which is the behaviour the store rule exists to prevent: history does not migrate
    /// between stores on a toggle. Here nothing migrates — the copy is written as an ordinary chat, it
    /// appears in the list, and the ephemeral original stays exactly as ephemeral as it was. The user
    /// opens the saved copy when they want to be in it.
    public func keepCopyOfCurrentChat() -> Conversation? {
        guard temporaryChat, let session else { return nil }
        do {
            let chat = session.conversation
            let copy = ChatDuplication.entireChat(
                chat,
                nodes: try ephemeralStore.nodes(conversationID: chat.id)
            )
            // The copy is an ordinary chat. A row that still said `isTemporary` would be refused by the
            // persistent store, and that refusal is the rule keeping temporary chats off disk — so the
            // copy declares itself honestly rather than slipping past the guard.
            var saved = copy.conversation
            saved.isTemporary = false
            try persistentStore.saveConversation(saved)
            for node in copy.nodes { try persistentStore.saveNode(node) }
            reloadConversations()
            return saved
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Out and back in

    /// The readable copy of one chat, or of every saved chat when `conversationID` is nil.
    ///
    /// Only the persistent store is read, which is what keeps a temporary chat out of an exported file:
    /// the thing the user chose to have forgotten is not something an export should quietly hand back. The
    /// way to export a temporary chat is to keep a copy of it first, and say so.
    public func transcriptMarkdown(conversationID: UUID? = nil) -> String? {
        do {
            if let conversationID {
                guard let chat = try persistentStore.conversation(id: conversationID) else {
                    lastError = StoreError.conversationNotFound(conversationID).errorDescription
                    return nil
                }
                return ChatTranscript.markdown(
                    conversation: chat,
                    nodes: try persistentStore.nodes(conversationID: conversationID)
                )
            }
            let chats = try persistentStore.loadConversations()
            guard !chats.isEmpty else {
                lastError = "There are no saved chats to export."
                return nil
            }
            var messages: [ChatNode] = []
            for chat in chats {
                messages.append(contentsOf: try persistentStore.nodes(conversationID: chat.id))
            }
            return ChatTranscript.markdown(conversations: chats, nodes: messages)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// The `.cairn` file of one chat, or of every saved chat. Lossless where the transcript is readable.
    public func exportFileData(conversationID: UUID? = nil) -> Data? {
        do {
            if let conversationID {
                guard let chat = try persistentStore.conversation(id: conversationID) else {
                    lastError = StoreError.conversationNotFound(conversationID).errorDescription
                    return nil
                }
                return try ChatExport.data(
                    conversations: [chat],
                    nodes: try persistentStore.nodes(conversationID: conversationID)
                )
            }
            let chats = try persistentStore.loadConversations()
            guard !chats.isEmpty else {
                lastError = "There are no saved chats to export."
                return nil
            }
            var messages: [ChatNode] = []
            for chat in chats {
                messages.append(contentsOf: try persistentStore.nodes(conversationID: chat.id))
            }
            return try ChatExport.data(conversations: chats, nodes: messages)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Opens a `.cairn` file into the saved store.
    ///
    /// An import always lands in the persistent store as an ordinary chat, never in the ephemeral one: a
    /// file the user opened is something they chose to keep, and writing it into the temporary store would
    /// lose it at the next launch. Id collisions are handled inside `ChatImport` by re-ids-ing the whole
    /// file as a copy, so an import can never overwrite a chat that is already here.
    public func importChatFile(_ data: Data) -> ChatImportPlan? {
        do {
            let plan = try ChatImport.apply(try ChatExport.decode(data), to: persistentStore)
            reloadConversations()
            return plan
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}

