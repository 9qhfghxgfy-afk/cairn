import Foundation
import Observation

/// Drives one conversation: appends nodes to the tree, streams a provider into it,
/// persists partial output as it arrives, and honors cancellation.
///
/// Views talk to this and nothing else. It never touches URLSession or SwiftData
/// directly — only `InferenceProvider` and `ChatStore`.
@Observable @MainActor
public final class ChatSessionModel {
    // Getters are public; setters are module-internal so the streaming core in
    // ChatSessionModel+Streaming.swift (same type, other file) can advance state.
    public internal(set) var conversation: Conversation
    public internal(set) var nodes: [ChatNode] = []
    public internal(set) var path: [ChatNode] = []
    public internal(set) var accumulator = StreamAccumulator()
    /// Live multi-candidate state while a hybrid turn is in flight. `nil` for every other turn,
    /// and left standing after a hybrid turn ends so the panels can still be read until the next
    /// turn starts.
    public internal(set) var hybrid: HybridSnapshot?
    public internal(set) var availableModels: [ModelInfo] = []
    public internal(set) var isBusy = false

    public var selectedProviderID: String
    public var selectedModelID: String
    public var lastError: String?
    /// The shared server choice (which server is active, and what each server was last used
    /// with). Optional so a session built without it — tests, the offline mock wiring — keeps
    /// working exactly as before and simply remembers nothing.
    public var selection: ServerSelectionModel?

    /// The on-device residency answer a hybrid turn needs. Only the app layer can read the real
    /// memory ceiling, so it injects the answer here; the default is the strict rule — one
    /// on-device model resident, released before the next one runs.
    public var residency: any HybridResidencyGating = NeverTwoOnDeviceResident()

    /// Models read from each engine, keyed by engine id. A hybrid turn asks several engines at
    /// once, so the picker has to name real models for a server that is not the one currently
    /// selected — and say so when it read none.
    public internal(set) var modelsByEngine: [String: [ModelInfo]] = [:]

    /// The clock and device facts the injected context is built from. Held on the session rather
    /// than read at the moment of assembly so the sheet's live preview and the turn that preview
    /// describes cannot drift apart; a test pins it, the app sets it once at startup.
    public var contextEnvironment: ContextEnvironment = .current()

    // Module-internal by design (not `private`, which is file-scoped in Swift):
    // the tree entry points in this file and the streaming core in
    // ChatSessionModel+Streaming.swift are two files of the same type.
    let store: any ChatStore
    let providers: [String: any InferenceProvider]
    /// When set, the live registry (server profiles can come and go) wins over
    /// the static snapshot; the static path keeps tests and M1 wiring intact.
    let registry: ProviderRegistry?
    var streamTask: Task<Void, Never>?

    public init(
        conversation: Conversation,
        store: any ChatStore,
        providers: [any InferenceProvider]
    ) {
        self.conversation = conversation
        self.store = store
        self.providers = Dictionary(
            providers.map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )
        self.registry = nil
        self.selectedProviderID = providers.first?.id ?? "mock"
        self.selectedModelID = ""
    }

    public init(
        conversation: Conversation,
        store: any ChatStore,
        registry: ProviderRegistry
    ) {
        self.conversation = conversation
        self.store = store
        self.providers = [:]
        self.registry = registry
        self.selectedProviderID = registry.providers.first?.id ?? "mock"
        self.selectedModelID = ""
    }

    public var activeProvider: (any InferenceProvider)? {
        if let fromRegistry = registry?.provider(id: selectedProviderID) {
            return fromRegistry
        }
        return providers[selectedProviderID]
    }

    /// True only if a provider actually emitted reasoning for this turn.
    public var showsReasoningPanel: Bool { accumulator.hasReasoning }
    public var liveTokensPerSecond: Double? { accumulator.metrics?.tokensPerSecond }
    public var phase: GenerationPhase { accumulator.phase }

    // MARK: - Loading

    public func bootstrap() async {
        do {
            nodes = try store.nodes(conversationID: conversation.id)
            path = ChatTree.visiblePath(nodes: nodes, activeLeafID: conversation.activeLeafID)
        } catch {
            lastError = error.localizedDescription
        }
        await loadModels()
    }

    public func loadModels() async {
        guard let provider = activeProvider else { return }
        do {
            let models = try await provider.models()
            availableModels = models
            // A remembered id may not exist on this server; fall back rather than send a
            // name the server does not know.
            if selectedModelID.isEmpty || !models.contains(where: { $0.id == selectedModelID }) {
                selectedModelID = models.first?.id ?? ""
            }
            recordSelectedModel()
        } catch {
            availableModels = []
            lastError = error.localizedDescription
        }
    }

    public func select(providerID: String) {
        guard registry?.provider(id: providerID) != nil || providers[providerID] != nil else {
            return
        }
        selectedProviderID = providerID
        restoreLastModel()
        Task { await loadModels() }
    }

    /// Points the session at one saved server and restores what that server was last used with,
    /// **without** loading its catalog. `bootstrap()` does that right after, and its result — a
    /// model id the server really has — is what should end up in `selectedModelID`.
    public func apply(serverProfileID profileID: UUID) {
        let engineID = RemoteEngineID.make(profileID: profileID)
        guard registry?.provider(id: engineID) != nil || providers[engineID] != nil else { return }
        selectedProviderID = engineID
        restoreLastModel()
    }

    /// One-tap switch from the Servers screen or the top bar of a chat: repoint the session at a
    /// saved server, make it the shared active server, then go and fetch its models. The session
    /// owns the reload, so no view has to know that switching and refreshing are two steps.
    public func select(serverProfileID profileID: UUID) {
        apply(serverProfileID: profileID)
        // Choosing a server in a chat *is* the choice for the whole app: writing it through here
        // is what makes the Servers screen agree on the next reload without either view polling
        // the other.
        selection?.setActive(profileID)
        Task { await loadModels() }
    }

    /// Picks a model for the current server and remembers it against that server only.
    public func choose(model modelID: String) {
        selectedModelID = modelID
        recordSelectedModel()
    }

    private func restoreLastModel() {
        guard let profileID = RemoteEngineID.parse(selectedProviderID) else {
            selectedModelID = ""
            return
        }
        selectedModelID = selection?.lastModel(forProfile: profileID) ?? ""
    }

    /// Writes the current model back to the shared selection. This is what makes "last model"
    /// mean *last used with this server*: the key is the profile, never the model name.
    private func recordSelectedModel() {
        guard let profileID = RemoteEngineID.parse(selectedProviderID),
              !selectedModelID.isEmpty else { return }
        selection?.remember(modelID: selectedModelID, forProfile: profileID)
    }

    // MARK: - Sending

    public func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard let provider = activeProvider else {
            lastError = "No inference provider is selected."
            return
        }

        var working = nodes
        do {
            let userTurn = ChatTree.append(
                to: working,
                conversationID: conversation.id,
                parentID: conversation.activeLeafID,
                role: .user,
                text: text,
                now: Date()
            )
            working = userTurn.nodes
            try store.saveNode(userTurn.node)

            var updated = conversation
            updated.activeLeafID = userTurn.node.id
            updated.updatedAt = Date()
            if updated.title == "New chat" { updated.title = Self.makeTitle(from: text) }
            try store.saveConversation(updated)

            let assistantTurn = ChatTree.append(
                to: working,
                conversationID: conversation.id,
                parentID: userTurn.node.id,
                role: .assistant,
                text: "",
                kind: ChatTree.hybridKind(for: conversation.mode) ?? .plain,
                state: .streaming,
                providerID: provider.id,
                modelID: selectedModelID,
                now: Date()
            )
            working = assistantTurn.nodes
            try store.saveNode(assistantTurn.node)

            updated.activeLeafID = assistantTurn.node.id
            try store.saveConversation(updated)

            conversation = updated
            nodes = working
            path = ChatTree.visiblePath(nodes: working, activeLeafID: assistantTurn.node.id)
            // One turn, one node — but a hybrid turn drives several engines and writes that one
            // node from the outcome, so it takes a different drain.
            if conversation.mode.isHybrid {
                beginHybridTurn(assistantNodeID: assistantTurn.node.id)
            } else {
                beginStreaming(assistantNodeID: assistantTurn.node.id, provider: provider)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
