import XCTest
@testable import CairnChatDomain

/// Continue Generation and the backgrounding interrupt, against the mock engine and the memory store.
///
/// The tree rule is what these tests exist to protect: continuing never rewrites the stopped answer. A
/// sibling is appended under the same parent, seeded with the text that already landed, and streams the
/// rest into that. If this ever mutates in place, the short answer the user stopped disappears.
@MainActor
final class ChatSessionContinueTests: XCTestCase {

    /// A stopped answer: send, wait for real text to arrive, then stop it.
    private func stoppedSession(
        byInterrupt: Bool = false
    ) async throws -> (ChatSessionModel, EphemeralStore, ChatNode) {
        let slow = MockStreamingProvider(thinkingCapable: false, tokenDelayNanoseconds: 40_000_000)
        let (model, store) = try SessionHarness.makeSession(provider: slow, thinkingEnabled: false)
        await model.bootstrap()
        model.send("count slowly")
        await SessionHarness.awaitSomeContent(model)
        if byInterrupt { model.interruptActiveTurn() } else { model.cancelStreaming() }
        await SessionHarness.settle(model)
        let stopped = try XCTUnwrap(model.path.last)
        XCTAssertFalse(stopped.text.isEmpty, "a stopped turn must keep the text that landed")
        return (model, store, stopped)
    }

    func testUserStopIsCancelledAndBackgroundingIsInterrupted() async throws {
        let (stoppedByUser, _, stoppedUserNode) = try await stoppedSession()
        XCTAssertEqual(stoppedUserNode.state, .cancelled)

        let (_, _, stoppedByBackground) = try await stoppedSession(byInterrupt: true)
        XCTAssertEqual(
            stoppedByBackground.state, .interrupted,
            "a backgrounding is not the user pressing Stop, and the row has to say which happened"
        )
        XCTAssertTrue(stoppedByUser.canContinue(stoppedUserNode))
        XCTAssertTrue(stoppedByUser.canContinue(stoppedByBackground))
    }

    func testContinueAppendsASiblingAndLeavesTheStoppedAnswerAlone() async throws {
        let (model, store, stopped) = try await stoppedSession()
        let askedID = try XCTUnwrap(stopped.parentID)

        model.continueGeneration(nodeID: stopped.id)
        await SessionHarness.settle(model)

        let continued = try XCTUnwrap(model.path.last)
        XCTAssertNotEqual(continued.id, stopped.id, "continuing must not write back into the stopped node")
        XCTAssertEqual(continued.parentID, askedID, "the continuation is a sibling, not a child of the answer")
        XCTAssertGreaterThan(continued.branchIndex, stopped.branchIndex)
        XCTAssertTrue(continued.text.hasPrefix(stopped.text), "the text that landed must carry into the sibling")
        XCTAssertGreaterThan(continued.text.count, stopped.text.count, "and the rest must arrive on top of it")
        XCTAssertEqual(continued.state, .complete)
        XCTAssertEqual(model.conversation.activeLeafID, continued.id)

        // The stopped answer is still there, unchanged, as the branch before it — which is what makes the
        // whole operation reversible from the branch switcher.
        let stored = try store.nodes(conversationID: model.conversation.id)
        let preserved = try XCTUnwrap(stored.first { $0.id == stopped.id })
        XCTAssertEqual(preserved.state, .cancelled)
        XCTAssertEqual(preserved.text, stopped.text)
        XCTAssertEqual(stored.filter { $0.role == .assistant }.count, 2)

        model.moveBranch(nodeID: continued.id, delta: -1)
        XCTAssertEqual(model.path.last?.id, stopped.id, "the short answer is still reachable")
    }

    func testContinueRefusesAFinishedAnswerAndSaysWhyWithoutTouchingTheTree() async throws {
        let (model, store) = try SessionHarness.makeSession(thinkingEnabled: false)
        await model.bootstrap()
        model.send("a whole answer")
        await SessionHarness.settle(model)
        let done = try XCTUnwrap(model.path.last)
        XCTAssertEqual(done.state, .complete)
        let before = try store.nodes(conversationID: model.conversation.id).count

        model.continueGeneration(nodeID: done.id)
        await SessionHarness.settle(model)

        XCTAssertEqual(model.lastError, ChatContinuation.nothingToContinue)
        XCTAssertEqual(model.path.last?.id, done.id)
        XCTAssertEqual(try store.nodes(conversationID: model.conversation.id).count, before)
    }

    func testTheInterruptFlagDoesNotStickIntoTheNextTurn() async throws {
        let slow = MockStreamingProvider(thinkingCapable: false, tokenDelayNanoseconds: 40_000_000)
        let (model, _) = try SessionHarness.makeSession(provider: slow, thinkingEnabled: false)
        await model.bootstrap()
        model.send("first, backgrounded")
        await SessionHarness.awaitSomeContent(model)
        model.interruptActiveTurn()
        await SessionHarness.settle(model)
        XCTAssertEqual(model.path.last?.state, .interrupted)

        model.send("second, finished normally")
        await SessionHarness.settle(model)
        XCTAssertEqual(
            model.path.last?.state, .complete,
            "a turn after a backgrounding must not be written as though the app had backgrounded again"
        )
    }

    func testAContinuationThatIsStoppedAgainStillHoldsAWholeAnswer() async throws {
        let (model, _, stopped) = try await stoppedSession()
        model.continueGeneration(nodeID: stopped.id)
        await SessionHarness.awaitSomeContent(model)
        model.cancelStreaming()
        await SessionHarness.settle(model)

        let again = try XCTUnwrap(model.path.last)
        XCTAssertEqual(again.state, .cancelled)
        XCTAssertTrue(
            again.text.hasPrefix(stopped.text),
            "stopping a continuation halfway must not leave half of an answer as its own branch"
        )
        XCTAssertTrue(model.canContinue(again), "and it can be continued again from there")
    }
}
