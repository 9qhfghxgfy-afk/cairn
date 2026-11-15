import Foundation

/// A working chat tree you cannot use wrong.
///
/// The pure `ChatTree` functions are value-in / value-out, which is great for
/// reasoning and testing but makes it easy to write `let x = append(...).node` and
/// silently throw away the returned array — leaving parents missing from the tree.
/// CI caught exactly that mistake, so this type wraps it: every mutation keeps the
/// array, and the returned node is `@discardableResult`.
public struct ChatDraftTree {
    public private(set) var nodes: [ChatNode]

    public init(nodes: [ChatNode] = []) {
        self.nodes = nodes
    }

    public var count: Int { nodes.count }

    @discardableResult
    public mutating func append(
        conversationID: UUID,
        parentID: UUID?,
        role: ChatRole,
        text: String = "",
        kind: NodeKind = .plain,
        state: NodeState = .complete,
        providerID: String? = nil,
        modelID: String? = nil,
        now: Date = Date()
    ) -> ChatNode {
        let result = ChatTree.append(
            to: nodes,
            conversationID: conversationID,
            parentID: parentID,
            role: role,
            text: text,
            kind: kind,
            state: state,
            providerID: providerID,
            modelID: modelID,
            now: now
        )
        nodes = result.nodes
        return result.node
    }

    @discardableResult
    public mutating func edit(nodeID: UUID, newText: String, now: Date = Date()) -> ChatNode? {
        guard let result = ChatTree.edit(nodes: nodes, nodeID: nodeID, newText: newText, now: now) else {
            return nil
        }
        nodes = result.nodes
        return result.node
    }

    @discardableResult
    public mutating func regenerate(
        assistantNodeID: UUID,
        providerID: String?,
        modelID: String?,
        now: Date = Date()
    ) -> ChatNode? {
        guard let result = ChatTree.regenerate(
            nodes: nodes,
            assistantNodeID: assistantNodeID,
            providerID: providerID,
            modelID: modelID,
            now: now
        ) else {
            return nil
        }
        nodes = result.nodes
        return result.node
    }

    @discardableResult
    public mutating func appendSynthesized(
        conversationID: UUID,
        parentID: UUID?,
        drafts: [CandidateDraft],
        providerID: String?,
        modelID: String?,
        now: Date = Date()
    ) -> ChatNode {
        let result = ChatTree.synthesizedNode(
            nodes: nodes,
            conversationID: conversationID,
            parentID: parentID,
            drafts: drafts,
            providerID: providerID,
            modelID: modelID,
            now: now
        )
        nodes = result.nodes
        return result.node
    }

    public func node(id: UUID) -> ChatNode? { nodes.first { $0.id == id } }

    public func children(of parentID: UUID?) -> [ChatNode] { ChatTree.children(of: parentID, in: nodes) }

    public func siblings(of node: ChatNode) -> [ChatNode] { ChatTree.siblings(of: node, in: nodes) }

    public func visiblePath(activeLeafID: UUID?) -> [ChatNode] {
        ChatTree.visiblePath(nodes: nodes, activeLeafID: activeLeafID)
    }

    public func branchPosition(of node: ChatNode) -> ChatTree.BranchPosition {
        ChatTree.branchPosition(of: node, in: nodes)
    }
}
