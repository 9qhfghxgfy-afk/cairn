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
    /// What the user attached to this message, as metadata only.
    ///
    /// Optional rather than an empty array because a file written before M6 has no such key, and because a
    /// message that carried nothing should write the same bytes it always did. nil means "the file never
    /// said", which reads back as "nothing attached" — the same answer a missing column gives in
    /// `ChatRecord`, for the same reason.
    ///
    /// The bytes are not here, deliberately: see `ExportedAttachment`.
    public var attachments: [ExportedAttachment]?
    /// The passages this answer was grounded in — file name, place in the file, ranking score, and a bounded
    /// quote. Numbers and a name and a short quote only; the document itself is not in the file.
    public var citations: [SourceCitation]?

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
        // Metadata, never the file: what a reader of this export can learn about an attachment is what the
        // row itself knows — the name, the kind, the size, and the text Cairn read from a document here.
        self.attachments = ExportedAttachments.export(node.attachments)
        self.citations = node.citations.isEmpty ? nil : node.citations
    }

    /// nil when any of the three enums, or an attachment's kind, carries a value this build does not have —
    /// again a refusal, not a guess. A message is never silently re-typed into the nearest known kind, and
    /// an attachment is never re-typed into the nearest known kind either: image and document differ in what
    /// may leave the device, so guessing would be a privacy decision made on the app's own behalf.
    public func toNode() -> ChatNode? {
        guard let nodeRole = ChatRole(rawValue: role),
              let nodeKind = NodeKind(rawValue: kind),
              let nodeState = NodeState(rawValue: state) else { return nil }
        // An attachment comes back with no bytes, which is what the file holds. The row that stores it then
        // has no file beside it either, so `attachmentPayload` answers nil and the app says the file is
        // gone rather than inventing pixels.
        var restored: [ChatAttachment] = []
        for entry in attachments ?? [] {
            guard let attachment = entry.toAttachment() else { return nil }
            restored.append(attachment)
        }
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
            toolRun: toolRun,
            attachments: restored,
            citations: citations ?? []
        )
    }
}
