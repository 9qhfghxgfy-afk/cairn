import Foundation
import Observation

/// Owns which store a chat lives in, which provider answers, and the current session.
///
/// The important privacy decision lives here: Temporary Chat is a STORE CHOICE, not a
/// flag the UI has to remember to honour. A temporary conversation is created in
/// `EphemeralStore`, so there is no code path that can write it to disk.
@Observable @MainActor
public final class ChatWorkspace {
    public private(set) var session: ChatSessionModel?
    public private(set) var conversations: [Conversation] = []
    public var lastError: String?

    public var temporaryChat: Bool {
        didSet {
            guard oldValue != temporaryChat else { return }
            // Toggling never moves history between stores: it starts a chat in the
            // store that matches the new mode, so nothing persisted can leak into an
            // ephemeral session and nothing ephemeral can be flushed to disk.
            startNewChat()
        }
    }

    public var mode: InferenceMode {
        didSet { applyMode(mode) }
    }

    private let persistentStore: any ChatStore
    private let ephemeralStore: EphemeralStore
    private let providerList: [any InferenceProvider]

    public init(
        persistentStore: any ChatStore,
        ephemeralStore: EphemeralStore = EphemeralStore(),
        providers: [any InferenceProvider],
        mode: InferenceMode = .onDeviceOnly,
        temporaryChat: Bool = false
    ) {
        self.persistentStore = persistentStore
        self.ephemeralStore = ephemeralStore
        self.providerList = providers
        self.mode = mode
        self.temporaryChat = temporaryChat
    }

    public var activeStore: any ChatStore {
        temporaryChat ? ephemeralStore : persistentStore
    }

    /// Ids of every configured engine, for the selector in the UI layer.
    public var providerIDs: [String] { providerList.map(\.id) }

    public func start() async {
        do {
            conversations = try persistentStore.loadConversations()
            if !temporaryChat, let mostRecent = conversations.first {
                bind(to: mostRecent)
            } else {
                createAndBind()
            }
        } catch {
            lastError = error.localizedDescription
            createAndBind()
        }
        await session?.bootstrap()
    }

    public func startNewChat() {
        createAndBind()
        Task { await session?.bootstrap() }
    }

    public func select(conversationID: UUID) {
        guard !temporaryChat, let conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        bind(to: conversation)
        Task { await session?.bootstrap() }
    }

    public func delete(conversationID: UUID) {
        do {
            try persistentStore.deleteConversation(id: conversationID)
            conversations = try persistentStore.loadConversations()
            if session?.conversation.id == conversationID { startNewChat() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func reloadConversations() {
        do {
            conversations = try persistentStore.loadConversations()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func createAndBind() {
        do {
            let conversation = try activeStore.createConversation(
                title: "New chat",
                mode: mode,
                params: .default,
                isTemporary: temporaryChat
            )
            session = ChatSessionModel(conversation: conversation, store: activeStore, providers: providerList)
            if !temporaryChat { reloadConversations() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func bind(to conversation: Conversation) {
        session = ChatSessionModel(conversation: conversation, store: persistentStore, providers: providerList)
    }

    private func applyMode(_ newMode: InferenceMode) {
        guard var conversation = session?.conversation else { return }
        conversation.mode = newMode
        do {
            try activeStore.saveConversation(conversation)
            session?.conversation = conversation
        } catch {
            lastError = error.localizedDescription
        }
    }
}
