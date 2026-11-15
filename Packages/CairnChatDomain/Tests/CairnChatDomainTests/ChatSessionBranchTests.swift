import XCTest
@testable import CairnChatDomain

/// Milestone 1 gate: edit / regenerate / branch navigation on the persisted tree.
@MainActor
final class ChatSessionBranchTests: XCTestCase {

    func testRegenerateCreatesASecondBranchTheStepperCanMoveBetween() async throws {
        let (model, store) = try SessionHarness.makeSession()
        await model.bootstrap()

        model.send("first question")
        await SessionHarness.settle(model)
        let firstAnswer = model.path.last!
        XCTAssertEqual(model.branchPosition(of: firstAnswer).total, 1)

        model.regenerate(assistantNodeID: firstAnswer.id)
        await SessionHarness.settle(model)

        let secondAnswer = model.path.last!
        XCTAssertNotEqual(secondAnswer.id, firstAnswer.id)

        let position = model.branchPosition(of: secondAnswer)
        XCTAssertEqual(position.total, 2)
        XCTAssertEqual(position.index, 2)

        model.moveBranch(nodeID: secondAnswer.id, delta: -1)
        XCTAssertEqual(model.path.last?.id, firstAnswer.id, "stepping back shows the older answer")

        model.moveBranch(nodeID: firstAnswer.id, delta: 1)
        XCTAssertEqual(model.path.last?.id, secondAnswer.id, "stepping forward returns to the newer answer")

        // Both answers exist as siblings under the same user turn.
        let stored = try store.nodes(conversationID: model.conversation.id)
        let answers = ChatTree.children(of: firstAnswer.parentID, in: stored).filter { $0.role == .assistant }
        XCTAssertEqual(answers.count, 2)
    }

    func testEditingAUserTurnKeepsTheOldBranchAndRepointsTheLeaf() async throws {
        let (model, store) = try SessionHarness.makeSession()
        await model.bootstrap()

        model.send("original question")
        await SessionHarness.settle(model)
        let originalUser = model.path.first!
        let firstAnswer = model.path.last!

        model.edit(nodeID: originalUser.id, newText: "corrected question")
        let editedUser = model.path.last!
        XCTAssertEqual(editedUser.role, .user)
        XCTAssertEqual(editedUser.text, "corrected question")
        XCTAssertEqual(model.branchPosition(of: editedUser).total, 2)

        // The previous answer and its parent are untouched.
        let stored = try store.nodes(conversationID: model.conversation.id)
        XCTAssertEqual(stored.first(where: { $0.id == originalUser.id })?.text, "original question")
        XCTAssertTrue(stored.contains { $0.id == firstAnswer.id })

        // A new send hangs off the edited node, so it opens a fresh branch.
        model.send("follow up on the correction")
        await SessionHarness.settle(model)
        let path = model.path
        XCTAssertEqual(path.first?.text, "corrected question")
        XCTAssertEqual(path.last?.role, .assistant)
        XCTAssertFalse(
            ChatTree.visiblePath(nodes: stored, activeLeafID: firstAnswer.id).isEmpty,
            "the abandoned branch is still walkable"
        )
    }

    func testTemporaryChatLivesOnlyInMemory() async throws {
        let (model, store) = try SessionHarness.makeSession(temporary: true)
        await model.bootstrap()
        XCTAssertTrue(model.conversation.isTemporary)

        model.send("nothing hits the disk")
        await SessionHarness.settle(model)

        XCTAssertEqual(try store.nodes(conversationID: model.conversation.id).count, 2)

        // A brand new ephemeral store is empty: there is no shared on-disk state.
        let fresh = EphemeralStore()
        XCTAssertEqual(try fresh.loadConversations().count, 0)
        XCTAssertEqual(try fresh.nodes(conversationID: model.conversation.id).count, 0)
    }
}
