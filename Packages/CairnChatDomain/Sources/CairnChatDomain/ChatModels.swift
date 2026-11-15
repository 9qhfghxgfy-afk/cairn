import Foundation

public enum ChatRole: String, Sendable, Equatable, Codable, CaseIterable {
    case system
    case user
    case assistant
}

public enum NodeKind: String, Sendable, Equatable, Codable {
    case plain
    /// A Hybrid Synthesized turn: ONE assistant node that carries the candidate
    /// drafts it was built from, so it replays and exports as a single node.
    case synthesized
}

public enum NodeState: String, Sendable, Equatable, Codable {
    case complete
    case streaming
    case cancelled
    case failed
    /// Persisted partial output that survived backgrounding; resumed via Continue.
    case interrupted
}

public enum InferenceMode: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case onDeviceOnly
    case remoteOnly
    case hybridParallel
    case hybridSynthesized

    public var id: String { rawValue }

    public var needsRemote: Bool {
        switch self {
        case .onDeviceOnly: return false
        case .remoteOnly, .hybridParallel, .hybridSynthesized: return true
        }
    }

    public var needsOnDevice: Bool {
        switch self {
        case .remoteOnly: return false
        case .onDeviceOnly, .hybridParallel, .hybridSynthesized: return true
        }
    }

    /// True when this mode can move data off the device.
    public var leavesDevice: Bool { needsRemote }
}

/// Per-chat sampling knobs (Milestone 3 wires these to real backends).
public struct SamplingParams: Sendable, Equatable, Codable {
    public var temperature: Double
    public var topP: Double
    public var repeatPenalty: Double
    public var maxTokens: Int
    public var contextWindow: Int
    public var thinkingEnabled: Bool
    public var systemPrompt: String

    public init(
        temperature: Double = 0.7,
        topP: Double = 0.95,
        repeatPenalty: Double = 1.1,
        maxTokens: Int = 1024,
        contextWindow: Int = 4096,
        thinkingEnabled: Bool = false,
        systemPrompt: String = ""
    ) {
        self.temperature = temperature
        self.topP = topP
        self.repeatPenalty = repeatPenalty
        self.maxTokens = maxTokens
        self.contextWindow = contextWindow
        self.thinkingEnabled = thinkingEnabled
        self.systemPrompt = systemPrompt
    }

    public static let `default` = SamplingParams()
}

/// One candidate answer inside a synthesized node.
public struct CandidateDraft: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var order: Int
    public var sourceLabel: String
    public var providerID: String
    public var modelID: String
    public var text: String
    public var thinking: String?
    public var state: NodeState

    public init(
        id: UUID = UUID(),
        order: Int,
        sourceLabel: String,
        providerID: String,
        modelID: String,
        text: String = "",
        thinking: String? = nil,
        state: NodeState = .streaming
    ) {
        self.id = id
        self.order = order
        self.sourceLabel = sourceLabel
        self.providerID = providerID
        self.modelID = modelID
        self.text = text
        self.thinking = thinking
        self.state = state
    }
}

/// A single node in the chat tree. History is never rewritten: edit, regenerate,
/// and branch all APPEND a sibling and repoint the conversation's active leaf.
public struct ChatNode: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var conversationID: UUID
    /// `nil` means this node is a root.
    public var parentID: UUID?
    public var role: ChatRole
    public var kind: NodeKind
    public var text: String
    /// Non-nil only if the backend actually emitted reasoning.
    public var thinking: String?
    public var state: NodeState
    /// Position among siblings of the same parent, 0-based.
    public var branchIndex: Int
    public var providerID: String?
    public var modelID: String?
    public var createdAt: Date
    public var drafts: [CandidateDraft]
    /// Measured only when a provider emitted `.metrics`; never estimated.
    public var metrics: GenerationMetrics?

    public init(
        id: UUID = UUID(),
        conversationID: UUID,
        parentID: UUID?,
        role: ChatRole,
        kind: NodeKind = .plain,
        text: String = "",
        thinking: String? = nil,
        state: NodeState = .complete,
        branchIndex: Int = 0,
        providerID: String? = nil,
        modelID: String? = nil,
        createdAt: Date = Date(),
        drafts: [CandidateDraft] = [],
        metrics: GenerationMetrics? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.parentID = parentID
        self.role = role
        self.kind = kind
        self.text = text
        self.thinking = thinking
        self.state = state
        self.branchIndex = branchIndex
        self.providerID = providerID
        self.modelID = modelID
        self.createdAt = createdAt
        self.drafts = drafts
        self.metrics = metrics
    }
}

public struct Conversation: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    /// The only pointer that decides what the user sees.
    public var activeLeafID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var mode: InferenceMode
    public var params: SamplingParams
    /// In-memory only when true: never written to disk by any store.
    public var isTemporary: Bool

    public init(
        id: UUID = UUID(),
        title: String = "New chat",
        activeLeafID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        mode: InferenceMode = .onDeviceOnly,
        params: SamplingParams = .default,
        isTemporary: Bool = false
    ) {
        self.id = id
        self.title = title
        self.activeLeafID = activeLeafID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.params = params
        self.isTemporary = isTemporary
    }
}
