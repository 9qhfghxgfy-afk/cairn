import XCTest
@testable import CairnChatDomain

/// Branching is the part of this product easiest to get subtly wrong, so it is tested
/// as pure tree algebra: no store, no provider, no simulator.
final class ChatTreeBranchTests: XCTestCase {

    let cid = UUID()

    func testAppendAssignsMonotonicBranchIndexes() {
        var tree = ChatDraftTree()
        let first = tree.append(conversationID: cid, parentID: nil, role: .user, text: "a")
        let second = tree.append(conversationID: cid, parentID: nil, role: .user, text: "b")
        let third = tree.append(conversationID: cid, parentID: nil, role: .user, text: "c")

        XCTAssertEqual(first.branchIndex, 0)
        XCTAssertEqual(second.branchIndex, 1)
        XCTAssertEqual(third.branchIndex, 2)
        XCTAssertEqual(tree.children(of: nil).map(\.branchIndex), [0, 1, 2])
    }

    func testEditCreatesSiblingAndNeverRewritesHistory() {
        var tree = ChatDraftTree()
        let user = tree.append(conversationID: cid, parentID: nil, role: .user, text: "original")
        tree.append(conversationID: cid, parentID: user.id, role: .assistant, text: "reply")

        guard let edited = tree.edit(nodeID: user.id, newText: "corrected") else {
            return XCTFail("edit returned nil")
        }

        XCTAssertEqual(edited.parentID, user.parentID)
        XCTAssertEqual(edited.branchIndex, 1)
        XCTAssertEqual(edited.text, "corrected")
        XCTAssertEqual(tree.count, 3, "edit appends; it must not replace")
        XCTAssertEqual(tree.node(id: user.id)?.text, "original")

        // The old answer stays attached to the old user node: a real branch, not garbage.
        let oldBranch = tree.children(of: user.id)
        XCTAssertEqual(oldBranch.count, 1)
        XCTAssertEqual(oldBranch.first?.text, "reply")
    }

    func testRegenerateAttachesToTheSameUserTurn() {
        var tree = ChatDraftTree()
        let user = tree.append(conversationID: cid, parentID: nil, role: .user, text: "ask")
        let v1 = tree.append(conversationID: cid, parentID: user.id, role: .assistant, text: "v1")

        guard let v2 = tree.regenerate(
            assistantNodeID: v1.id, providerID: "mock", modelID: "cairn-mock-8b"
        ) else {
            return XCTFail("regenerate returned nil")
        }

        XCTAssertEqual(v2.parentID, user.id, "a regenerated answer hangs off the same user turn")
        XCTAssertEqual(v2.role, .assistant)
        XCTAssertEqual(v2.branchIndex, 1)
        XCTAssertEqual(v2.state, .streaming)
        XCTAssertTrue(v2.text.isEmpty)
        XCTAssertEqual(tree.children(of: user.id).count, 2)
        XCTAssertEqual(tree.count, 3, "the first answer is still there")
    }

    func testVisiblePathFollowsOnlyTheActiveLeaf() {
        var tree = ChatDraftTree()
        let userA = tree.append(conversationID: cid, parentID: nil, role: .user, text: "first")
        let answerA1 = tree.append(conversationID: cid, parentID: userA.id, role: .assistant, text: "answer one")
        let answerA2 = tree.append(conversationID: cid, parentID: userA.id, role: .assistant, text: "answer two")
        let userB = tree.append(conversationID: cid, parentID: answerA2.id, role: .user, text: "follow up")

        XCTAssertEqual(
            tree.visiblePath(activeLeafID: userB.id).map(\.text),
            ["first", "answer two", "follow up"]
        )
        XCTAssertEqual(
            tree.visiblePath(activeLeafID: answerA1.id).map(\.text),
            ["first", "answer one"]
        )
        XCTAssertEqual(tree.visiblePath(activeLeafID: nil), [])
    }

    /// Regression guard for the trap CI caught: the pure `ChatTree` functions return a
    /// NEW array, and dropping it silently leaves a tree with missing parents.
    func testDroppingTheReturnedArrayIsTheBugChatDraftTreePrevents() {
        let appended = ChatTree.append(to: [], conversationID: cid, parentID: nil, role: .user, text: "root")
        XCTAssertTrue(appended.nodes.contains { $0.id == appended.node.id })

        // Taking only `.node` and keeping an empty array is the exact mistake:
        var lostRoot = ChatDraftTree()
        XCTAssertNil(
            ChatTree.edit(nodes: lostRoot.nodes, nodeID: appended.node.id, newText: "x"),
            "a tree that lost its root cannot even find the node to edit"
        )

        // The draft tree keeps every append, so the same edit succeeds.
        var kept = ChatDraftTree()
        let root = kept.append(conversationID: cid, parentID: nil, role: .user, text: "root")
        let edited = ChatTree.edit(nodes: kept.nodes, nodeID: root.id, newText: "x")
        XCTAssertEqual(edited?.node.text, "x")
    }
}
