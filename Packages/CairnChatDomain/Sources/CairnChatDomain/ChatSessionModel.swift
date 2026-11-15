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
    public internal(set) var availableModels: [ModelInfo] = []
    public internal(set) var isBusy = false

    public var selectedProviderID: String
    public var selectedModelID: String
    public var lastError: String?

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
            if selectedModelID.isEmpty || !models.contains(where: { $0.id == selectedModelID }) {
                selectedModelID = models.first?.id ?? ""
            }
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
        selectedModelID = ""
        Task { await loadModels() }
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
            beginStreaming(assistantNodeID: assistantTurn.node.id, provider: provider)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
