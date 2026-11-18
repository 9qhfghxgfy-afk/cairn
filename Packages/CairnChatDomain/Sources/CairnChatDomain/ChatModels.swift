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
    /// A Hybrid Parallel turn: also ONE assistant node, holding both candidates as
    /// drafts. Its own text is the primary candidate's answer, so a later turn in this
    /// branch still gets a real assistant message even when the other side failed.
    case hybridParallel

    /// True for either Hybrid shape — one node, many drafts.
    public var isHybrid: Bool { self == .synthesized || self == .hybridParallel }
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

    /// True for the two Hybrid modes, which run more than one engine per turn and are
    /// driven by `HybridEngine` rather than by a single provider stream.
    public var isHybrid: Bool { self == .hybridParallel || self == .hybridSynthesized }
}

/// One candidate answer inside a hybrid node.
public struct CandidateDraft: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var order: Int
    public var sourceLabel: String
    public var providerID: String
    public var modelID: String
    public var text: String
    public var thinking: String?
    public var state: NodeState
    /// Measured from **this** candidate's own `.metrics` chunk. Never copied from another
    /// side and never estimated, because the Parallel panels show these numbers directly.
    public var metrics: GenerationMetrics?
    /// What this candidate's provider said when it failed, and nothing else. A failed draft
    /// is kept rather than dropped: one surviving answer is still an answer.
    public var failure: String?

    public init(
        id: UUID = UUID(),
        order: Int,
        sourceLabel: String,
        providerID: String,
        modelID: String,
        text: String = "",
        thinking: String? = nil,
        state: NodeState = .streaming,
        metrics: GenerationMetrics? = nil,
        failure: String? = nil
    ) {
        self.id = id
        self.order = order
        self.sourceLabel = sourceLabel
        self.providerID = providerID
        self.modelID = modelID
        self.text = text
        self.thinking = thinking
        self.state = state
        self.metrics = metrics
        self.failure = failure
    }

    /// A draft that can be shown as an answer: it finished and actually said something.
    public var answered: Bool { state == .complete && !text.isEmpty }
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
    /// What this turn was offered, kept so a transcript can say which tools the model could reach
    /// without re-deriving it from settings the user may have changed since. Empty for every message
    /// written before P3.
    public var toolsOffered: [String]
    /// Every call this answer was built from, in the order they ran, plus how many round trips they
    /// took and which protocol carried them. One value written whole, in its own column, for the same
    /// reason `HybridProvenance` is: several related facts about one node that would otherwise make
    /// every added field a schema migration. A node with no tools has no `ToolRun` at all — which is
    /// how a pre-P3 row keeps reading as "no tools ran" rather than "zero tools ran, somehow".
    public var toolRun: ToolRun?
    /// How a hybrid turn was produced: which engines were candidates, which one wrote the
    /// unified answer, and what failed. `nil` for every non-hybrid node and for every
    /// message written before M4.
    public var provenance: HybridProvenance?

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
        metrics: GenerationMetrics? = nil,
        provenance: HybridProvenance? = nil,
        toolsOffered: [String] = [],
        toolRun: ToolRun? = nil
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
        self.provenance = provenance
        self.toolsOffered = toolsOffered
        self.toolRun = toolRun
    }
}

// `Conversation` lives in Conversation.swift and `ChatConfig` in ChatConfig.swift: P2 moved the
// sampling knobs out of a flat `params` struct and gave each chat a configuration that can say
// "unset" as well as "set".

