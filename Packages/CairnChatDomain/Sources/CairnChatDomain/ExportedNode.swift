import Foundation

/// The on-disk shape of one message inside a `.cairn` file.
///
/// A node is written whole: its parent pointer and branch index, so the tree survives, plus the hybrid
/// drafts, the measured metrics, the provenance and the tool run, because those are the parts that make
/// an answer explainable later. Every field here is already a `Codable` domain value — no prompt text
/// from another chat, no server address, no credential — which is what lets the same file be shared by
/// AirDrop without a second thought about what it contains.
public struct ExportedNode: Sendable, Equatable, Codable {
    public var id: UUID
    public var conversationID: UUID
    public var parentID: UUID?
    public var role: String
    public var kind: String
    public var state: String
    public var text: String
    public var thinking: String?
    public var branchIndex: Int
    public var providerID: String?
    public var modelID: String?
    public var createdAt: Date
    public var drafts: [CandidateDraft]
    public var metrics: GenerationMetrics?
    public var provenance: HybridProvenance?
    public var toolsOffered: [String]
    public var toolRun: ToolRun?

    public init(_ node: ChatNode) {
        self.id = node.id
        self.conversationID = node.conversationID
        self.parentID = node.parentID
        self.role = node.role.rawValue
        self.kind = node.kind.rawValue
        self.state = node.state.rawValue
        self.text = node.text
        self.thinking = node.thinking
        self.branchIndex = node.branchIndex
        self.providerID = node.providerID
        self.modelID = node.modelID
        self.createdAt = node.createdAt
        self.drafts = node.drafts
        self.metrics = node.metrics
        self.provenance = node.provenance
        self.toolsOffered = node.toolsOffered
        self.toolRun = node.toolRun
    }

    /// nil when any of the three enums carries a value this build does not have — again a refusal, not
    /// a guess. A message is never silently re-typed into the nearest known kind.
    public func toNode() -> ChatNode? {
        guard let nodeRole = ChatRole(rawValue: role),
              let nodeKind = NodeKind(rawValue: kind),
              let nodeState = NodeState(rawValue: state) else { return nil }
        return ChatNode(
            id: id,
            conversationID: conversationID,
            parentID: parentID,
            role: nodeRole,
            kind: nodeKind,
            text: text,
            thinking: thinking,
            state: nodeState,
            branchIndex: branchIndex,
            providerID: providerID,
            modelID: modelID,
            createdAt: createdAt,
            drafts: drafts,
            metrics: metrics,
            provenance: provenance,
            toolsOffered: toolsOffered,
            toolRun: toolRun
        )
    }
}
