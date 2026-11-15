import Foundation

/// Pure tree operations. No store, no I/O, no dates unless injected — everything
/// here is unit-testable with plain arrays.
///
/// Invariants:
/// - A node's siblings are the other children of the same parent.
/// - `branchIndex` is monotonic within a parent; it is never reused or renumbered.
/// - Edit and regenerate create a SIBLING (same parent); they never mutate history.
/// - The conversation's `activeLeafID` alone decides what is visible.
public enum ChatTree {

    // MARK: - Queries

    public static func children(of parentID: UUID?, in nodes: [ChatNode]) -> [ChatNode] {
        nodes.filter { $0.parentID == parentID }
             .sorted { $0.branchIndex < $1.branchIndex }
    }

    public static func siblings(of node: ChatNode, in nodes: [ChatNode]) -> [ChatNode] {
        children(of: node.parentID, in: nodes)
    }

    public static func nextBranchIndex(in nodes: [ChatNode], parentID: UUID?) -> Int {
        (children(of: parentID, in: nodes).map(\.branchIndex).max() ?? -1) + 1
    }

    /// Root-first ordering of the path that ends at `leafID`.
    /// Bails out if a malformed parent chain revisits an id.
    public static func path(fromRootToLeaf leafID: UUID, in nodes: [ChatNode]) -> [ChatNode] {
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var walked: [ChatNode] = []
        var visited = Set<UUID>()
        var cursor: UUID? = leafID
        while let id = cursor, let node = byID[id] {
            if visited.contains(id) { break }
            visited.insert(id)
            walked.append(node)
            cursor = node.parentID
        }
        return walked.reversed()
    }

    public static func visiblePath(nodes: [ChatNode], activeLeafID: UUID?) -> [ChatNode] {
        guard let leafID = activeLeafID else { return [] }
        return path(fromRootToLeaf: leafID, in: nodes)
    }

    /// 1-based position and sibling count for the `< 1 / N >` branch stepper.
    public struct BranchPosition: Sendable, Equatable {
        public var index: Int
        public var total: Int
        public var canGoBack: Bool { index > 1 }
        public var canGoForward: Bool { index < total }

        public init(index: Int, total: Int) {
            self.index = index
            self.total = total
        }
    }

    public static func branchPosition(of node: ChatNode, in nodes: [ChatNode]) -> BranchPosition {
        let sibs = siblings(of: node, in: nodes)
        let idx = (sibs.firstIndex { $0.id == node.id } ?? 0) + 1
        return BranchPosition(index: idx, total: max(sibs.count, 1))
    }

    public static func hasSiblingBranches(of node: ChatNode, in nodes: [ChatNode]) -> Bool {
        siblings(of: node, in: nodes).count > 1
    }

    /// Flattens the active path into provider messages, oldest first.
    public static func messages(for path: [ChatNode], params: SamplingParams) -> [ChatMessagePayload] {
        var out: [ChatMessagePayload] = []
        if !params.systemPrompt.isEmpty {
            out.append(ChatMessagePayload(role: .system, text: params.systemPrompt))
        }
        for node in path where node.state != .failed {
            guard !node.text.isEmpty else { continue }
            out.append(ChatMessagePayload(role: node.role, text: node.text))
        }
        return out
    }
}
