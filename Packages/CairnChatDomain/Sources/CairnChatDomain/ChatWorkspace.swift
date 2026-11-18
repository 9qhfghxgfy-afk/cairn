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
    /// Which saved server the app should point its chats at, and what each server was last used
    /// with. Injected rather than reached for: `CairnAppUI` may not import SwiftData, so the App
    /// layer hands this in as a domain type.
    public let selection: ServerSelectionModel?

    /// The baseline every new chat is seeded from. The App layer hands in the Default Configuration
    /// from Settings; a workspace wired without one uses `ChatConfig.default`, which asserts no
    /// sampling knob and injects the default context.
    ///
    /// Seeding copies the baseline into the new conversation and never reads it again: re-resolving
    /// an existing chat against settings the user changed afterwards would rewrite history's
    /// behaviour behind their back.
    public var defaultConfig: ChatConfig = .default

    /// The memory answer a hybrid turn asks: may two on-device models be resident at one instant,
    /// and what has to be released before the next one loads.
    ///
    /// Only the app layer can read the real ceiling, so it injects one here; a workspace wired
    /// without a gate leaves every session on the domain's strict default, which is one on-device
    /// model at a time with a release between them. Set before `start()` so the first session a
    /// workspace makes already carries it.
    public var residency: (any HybridResidencyGating)?

    /// Points the baseline at a new Default Configuration. Existing chats keep what they were seeded
    /// with — only chats created from here on take it.
    public func apply(defaults: ChatConfig) {
        defaultConfig = defaults
    }

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
    /// Live registry when the app wires one (server profiles can change at
    /// runtime); the static list keeps tests and simple wiring working.
    private let registry: ProviderRegistry?

    public init(
        persistentStore: any ChatStore,
        ephemeralStore: EphemeralStore = EphemeralStore(),
        providers: [any InferenceProvider],
        mode: InferenceMode = .onDeviceOnly,
        temporaryChat: Bool = false,
        selection: ServerSelectionModel? = nil
    ) {
        self.persistentStore = persistentStore
        self.ephemeralStore = ephemeralStore
        self.providerList = providers
        self.registry = nil
        self.mode = mode
        self.temporaryChat = temporaryChat
        self.selection = selection
    }

    public init(
        persistentStore: any ChatStore,
        ephemeralStore: EphemeralStore = EphemeralStore(),
        registry: ProviderRegistry,
        mode: InferenceMode = .onDeviceOnly,
        temporaryChat: Bool = false,
        selection: ServerSelectionModel? = nil
    ) {
        self.persistentStore = persistentStore
        self.ephemeralStore = ephemeralStore
        self.providerList = []
        self.registry = registry
        self.mode = mode
        self.temporaryChat = temporaryChat
        self.selection = selection
    }

    public var activeStore: any ChatStore {
        temporaryChat ? ephemeralStore : persistentStore
    }

    /// Ids of every configured engine, for the selector in the UI layer.
    public var providerIDs: [String] {
        registry?.ids ?? providerList.map(\.id)
    }

    public func providerDisplayName(_ id: String) -> String {
        if let fromRegistry = registry?.displayName(for: id), fromRegistry != id {
            return fromRegistry
        }
        return providerList.first { $0.id == id }?.displayName ?? id
    }

    /// Where an engine's traffic goes, so a switcher can say "public" out loud instead of letting
    /// a name imply it. nil for an engine that is not registered.
    public func providerNetworkClass(_ id: String) -> NetworkClass? {
        (registry?.provider(id: id) ?? providerList.first { $0.id == id })?.networkClass
    }

    public func start() async {
        do {
            reloadConversations()
            if !temporaryChat, let mostRecent = conversations.first {
                // Re-read so the rebound session cannot inherit a stale activeLeafID.
                if let fresh = try persistentStore.conversation(id: mostRecent.id) {
                    bind(to: fresh)
                } else {
                    bind(to: mostRecent)
                }
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
        // The store is the source of truth. `conversations` is only a display
        // snapshot: reusing it here rebinds the session to a stale conversation
        // whose activeLeafID predates the last send, which silently shows an
        // empty transcript. Re-read the row instead.
        guard !temporaryChat else { return }
        do {
            guard let conversation = try persistentStore.conversation(id: conversationID) else {
                lastError = StoreError.conversationNotFound(conversationID).errorDescription
                return
            }
            bind(to: conversation)
            Task { await session?.bootstrap() }
        } catch {
            lastError = error.localizedDescription
        }
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

    private func makeSession(
        conversation: Conversation,
        store: any ChatStore
    ) -> ChatSessionModel {
        let session: ChatSessionModel
        if let registry {
            session = ChatSessionModel(conversation: conversation, store: store, registry: registry)
        } else {
            session = ChatSessionModel(conversation: conversation, store: store, providers: providerList)
        }
        session.selection = selection
        // The memory gate travels with the session, so a hybrid turn in this chat asks the real
        // device question rather than the domain default. Nil keeps the strict default in place.
        if let residency { session.residency = residency }
        // Applied before any view can read the session, so a new or reopened chat opens on
        // the server in use rather than on whatever the registry happens to list first.
        if let activeID = selection?.activeProfileID {
            session.apply(serverProfileID: activeID)
        }
        return session
    }

    /// Points the live session at the chosen server and restores that server's last model. The
    /// caller resolves *which* profile is active: `ServersModel` owns the saved list, and this
    /// module must not reach for a store.
    public func apply(activeProfile profile: ServerProfile) {
        guard profile.usableNow else { return }
        session?.apply(serverProfileID: profile.id)
        Task { await session?.loadModels() }
    }

    private func createAndBind() {
        do {
            let conversation = try activeStore.createConversation(
                title: "New chat",
                mode: mode,
                config: defaultConfig,
                isTemporary: temporaryChat
            )
            session = makeSession(conversation: conversation, store: activeStore)
            if !temporaryChat { reloadConversations() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func bind(to conversation: Conversation) {
        session = makeSession(conversation: conversation, store: persistentStore)
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
