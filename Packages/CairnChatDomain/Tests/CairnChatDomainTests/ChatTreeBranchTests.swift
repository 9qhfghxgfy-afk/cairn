import XCTest
@testable import CairnChatDomain

/// Branching is the part of this product easiest to get subtly wrong, so it is tested
/// as pure tree algebra: no store, no provider, no simulator.
final class ChatTreeBranchTests: XCTestCase {

    let cid = UUID()

    func testAppendAssignsMonotonicBranchIndexes() {
        let empty: [ChatNode] = []
        let first = ChatTree.append(to: empty, conversationID: cid, parentID: nil, role: .user, text: "a")
        let second = ChatTree.append(to: first.nodes, conversationID: cid, parentID: nil, role: .user, text: "b")
        let third = ChatTree.append(to: second.nodes, conversationID: cid, parentID: nil, role: .user, text: "c")

        XCTAssertEqual(first.node.branchIndex, 0)
        XCTAssertEqual(second.node.branchIndex, 1)
        XCTAssertEqual(third.node.branchIndex, 2)
        XCTAssertEqual(ChatTree.children(of: nil, in: third.nodes).map(\.branchIndex), [0, 1, 2])
    }

    func testEditCreatesSiblingAndNeverRewritesHistory() {
        var nodes: [ChatNode] = []
        let user = ChatTree.append(to: nodes, conversationID: cid, parentID: nil, role: .user, text: "original").node
        nodes = ChatTree.append(to: nodes, conversationID: cid, parentID: user.id, role: .assistant, text: "reply").nodes

        guard let edited = ChatTree.edit(nodes: nodes, nodeID: user.id, newText: "corrected") else {
            return XCTFail("edit returned nil")
        }

        XCTAssertEqual(edited.node.parentID, user.parentID)
        XCTAssertEqual(edited.node.branchIndex, 1)
        XCTAssertEqual(edited.node.text, "corrected")
        XCTAssertEqual(edited.nodes.count, 3, "edit appends; it must not replace")
        XCTAssertEqual(edited.nodes.first { $0.id == user.id }?.text, "original")

        // The old answer stays attached to the old user node: a real branch, not garbage.
        let oldBranch = ChatTree.children(of: user.id, in: edited.nodes)
        XCTAssertEqual(oldBranch.count, 1)
        XCTAssertEqual(oldBranch.first?.text, "reply")
    }

    func testRegenerateAttachesToTheSameUserTurn() {
        var nodes: [ChatNode] = []
        let user = ChatTree.append(to: nodes, conversationID: cid, parentID: nil, role: .user, text: "ask").node
        nodes = ChatTree.append(to: nodes, conversationID: cid, parentID: user.id, role: .assistant, text: "v1").nodes
        let v1 = nodes.last!

        guard let regen = ChatTree.regenerate(
            nodes: nodes, assistantNodeID: v1.id, providerID: "mock", modelID: "cairn-mock-8b"
        ) else { return XCTFail("regenerate returned nil") }

        XCTAssertEqual(regen.node.parentID, user.id, "a regenerated answer hangs off the same user turn")
        XCTAssertEqual(regen.node.role, .assistant)
        XCTAssertEqual(regen.node.branchIndex, 1)
        XCTAssertEqual(regen.node.state, .streaming)
        XCTAssertTrue(regen.node.text.isEmpty)
        XCTAssertEqual(ChatTree.children(of: user.id, in: regen.nodes).count, 2)
    }

    func testVisiblePathFollowsOnlyTheActiveLeaf() {
        var nodes: [ChatNode] = []
        let userA = ChatTree.append(to: nodes, conversationID: cid, parentID: nil, role: .user, text: "first").node
        nodes = ChatTree.append(to: nodes, conversationID: cid, parentID: userA.id, role: .assistant, text: "answer one").nodes
        let answerA1 = nodes.last!
        let answerA2 = ChatTree.append(
            to: nodes, conversationID: cid, parentID: userA.id, role: .assistant, text: "answer two"
        ).node
        nodes = ChatTree.append(to: nodes, conversationID: cid, parentID: answerA2.id, role: .user, text: "follow up").nodes
        let userB = nodes.last!

        XCTAssertEqual(
            ChatTree.visiblePath(nodes: nodes, activeLeafID: userB.id).map(\.text),
            ["first", "answer two", "follow up"]
        )
        XCTAssertEqual(
            ChatTree.visiblePath(nodes: nodes, activeLeafID: answerA1.id).map(\.text),
            ["first", "answer one"]
        )
        XCTAssertEqual(ChatTree.visiblePath(nodes: nodes, activeLeafID: nil), [])
    }
}
