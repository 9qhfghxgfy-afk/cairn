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

    /// The tools every session this workspace creates may reach, and the two switches that decide
    /// what a tool turn is allowed to do. Injected by the app: a workspace wired without them leaves
    /// every chat with no registry, no outbound acknowledgement and the metrics footer left on, which
    /// is what a test or an unwired build should get — tools that are never live just because the code
    /// to run them is compiled in.
    public var toolRegistry: ToolRegistry = .empty
    public var outboundWebAllowed: Bool = false
    public var showsGenerationStats: Bool = true

    /// Reads the stored bytes of one attachment, injected by the app because only the app layer owns the
    /// directory the files live in — `CairnChatDomain` never opens a file, and `CairnAppUI` may not import
    /// SwiftData. Nil by construction, which is what a test or an unwired workspace gets: a session that can
    /// describe an attachment and cannot read its bytes, and refuses to send it rather than sending nothing.
    public var attachmentReader: (@MainActor (UUID) -> Data?)?

    /// Whether the persistent store can keep an attached file between turns, written by the app from
    /// `SwiftDataStore.canStoreAttachments`. It travels to every session the workspace makes, so the
    /// composer's promise about a file agrees with the store that would have held it — and a temporary chat,
    /// which lives in `EphemeralStore`, is told the truth about itself separately.
    public var attachmentStorageAvailable: Bool = true

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

    // Module-internal rather than `private` (which is file-scoped in Swift): the chat-list actions in
    // ChatWorkspace+Chats.swift have to duplicate and copy between exactly these two stores and no
    // others. Which store is in play is still decided here, in `activeStore`, and nowhere else.
    let persistentStore: any ChatStore
    let ephemeralStore: EphemeralStore
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
        (engine(id: id))?.networkClass
    }

    /// The engine behind an id, or nil. Internal rather than public: the mode-routing extension in
    /// `ChatWorkspace+ModeRouting.swift` needs an engine's declared kind, and a `NetworkClass` alone
    /// cannot tell a real on-device model from the stand-in that answers a fresh install.
    func engine(id: String) -> (any InferenceProvider)? {
        registry?.provider(id: id) ?? providerList.first { $0.id == id }
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

    /// Re-points the workspace and its live session at a new tool surface.
    ///
    /// The app calls this at launch and again when the outbound acknowledgement changes. That second
    /// call is not decoration: a registry assembled before the user said "yes, web tools may go out"
    /// holds no web tools at all, so the chat they armed one second later would be left with a chip that
    /// offers arithmetic and nothing else — a switch that appears to work and does not.
    public func apply(
        tools registry: ToolRegistry,
        outboundWebAllowed: Bool,
        showsGenerationStats: Bool
    ) {
        toolRegistry = registry
        self.outboundWebAllowed = outboundWebAllowed
        self.showsGenerationStats = showsGenerationStats
        guard let session else { return }
        session.toolRegistry = registry
        session.outboundWebAllowed = outboundWebAllowed
        session.showsGenerationStats = showsGenerationStats
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
        // The tool surface travels with the session, for the same reason the memory gate does: the
        // app owns the registry and the two switches, and a chat opened before Settings was read must
        // still get the same answer as one opened after.
        session.toolRegistry = toolRegistry
        session.outboundWebAllowed = outboundWebAllowed
        session.showsGenerationStats = showsGenerationStats
        // The attachment reader travels the same way, and unconditionally: the workspace is the source of
        // truth for where a stored file's bytes come from, so a session never holds a reader its own store
        // cannot back. Nil is the honest value for an unwired workspace or a test.
        session.attachmentBytes = attachmentReader
        session.attachmentStorageAvailable = attachmentStorageAvailable
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
        // A mode is a routing decision, not a label. Before this, choosing "On device" saved the
        // word and left the session answering from the server it was already pointed at — a switch
        // that says one thing and does another, which is the failure this app is not allowed to have.
        routeEngines(for: newMode)
    }
}
