import XCTest
@testable import CairnChatDomain

/// Which answer may be picked up again, and what is said to the model when it is.
///
/// Continuing is not regenerating. The user wants the rest of *this* answer, so the rule has to be
/// precise about which turns have a "rest" at all — and the history it builds must show the model the
/// answer it is continuing, without inventing a message the user never typed.
final class ChatContinuationTests: XCTestCase {

    private func answer(
        state: NodeState,
        text: String = "Step one: unplug the",
        finish: FinishReason? = nil,
        kind: NodeKind = .plain
    ) -> ChatNode {
        ChatNode(
            conversationID: UUID(), parentID: nil, role: .assistant, kind: kind, text: text,
            state: state,
            metrics: finish.map { GenerationMetrics(tokensGenerated: 8, elapsedSeconds: 1, finishReason: $0) }
        )
    }

    func testATurnThatStoppedShortIsTheOneOfferedContinue() {
        XCTAssertTrue(ChatContinuation.canContinue(answer(state: .cancelled)))
        XCTAssertTrue(ChatContinuation.canContinue(answer(state: .interrupted)))
        // A server that says `length` cut the reply off mid-sentence even though the turn "completed".
        XCTAssertTrue(ChatContinuation.canContinue(answer(state: .complete, finish: .length)))
    }

    func testATurnWithNothingMissingIsNotOfferedContinue() {
        XCTAssertFalse(ChatContinuation.canContinue(answer(state: .complete, finish: .stop)))
        XCTAssertFalse(ChatContinuation.canContinue(answer(state: .complete)))
        XCTAssertFalse(ChatContinuation.canContinue(answer(state: .streaming)))
    }

    func testAFailedTurnIsRegeneratesJobNotContinues() {
        // Its own error is the story of a failed turn; appending more of the same stream would bury it.
        XCTAssertFalse(ChatContinuation.canContinue(answer(state: .failed)))
    }

    func testNothingToContinueIsNotOfferedForAnEmptyOrNonAssistantNode() {
        XCTAssertFalse(ChatContinuation.canContinue(answer(state: .cancelled, text: "")))
        XCTAssertFalse(ChatContinuation.canContinue(
            ChatNode(conversationID: UUID(), parentID: nil, role: .user, text: "hi", state: .cancelled)
        ))
    }

    func testAHybridAnswerIsNotContinuedBecauseItWasWrittenFromDrafts() {
        // A synthesized turn's text came from a second engine reading drafts; "the rest of it" is not one
        // stream's continuation, and pretending otherwise would attribute words to a model that never
        // generated them.
        XCTAssertFalse(ChatContinuation.canContinue(answer(state: .cancelled, kind: .synthesized)))
        XCTAssertFalse(ChatContinuation.canContinue(answer(state: .cancelled, kind: .hybridParallel)))
    }

    func testTheHistoryEndsWithTheInstructionAndShowsTheStoppedAnswerLast() {
        let chatID = UUID()
        let asked = ChatNode(conversationID: chatID, parentID: nil, role: .user, text: "how do I seal a cairn?")
        let stopped = ChatNode(
            conversationID: chatID, parentID: asked.id, role: .assistant,
            text: "Stack the", state: .cancelled
        )
        let untaken = ChatNode(
            conversationID: chatID, parentID: asked.id, role: .assistant,
            text: "Mortar it.", branchIndex: 1
        )

        let history = ChatContinuation.requestHistory([asked, stopped, untaken], stopped: stopped)
        XCTAssertEqual(history.map { $0.role }, [.user, .assistant, .user])
        XCTAssertEqual(history.map { $0.text }, [
            "how do I seal a cairn?", "Stack the", ChatContinuation.instruction(for: stopped),
        ])
        // The answer being continued is the last thing the model sees before the instruction, and the
        // branch the user walked away from stays out of the request.
        XCTAssertFalse(history.contains { $0.text == "Mortar it." })
        XCTAssertTrue(history[2].text.contains("Continue the answer above"))
    }

    func testTheWritingSiblingIsNotInTheHistoryItIsBeingAskedToFinish() {
        let chatID = UUID()
        let asked = ChatNode(conversationID: chatID, parentID: nil, role: .user, text: "question")
        let stopped = ChatNode(conversationID: chatID, parentID: asked.id, role: .assistant, text: "half", state: .cancelled)
        var writing = stopped
        writing.id = UUID()
        writing.text = "half"
        writing.state = .streaming
        writing.branchIndex = 1

        let history = ChatContinuation.requestHistory([asked, stopped, writing], stopped: stopped)
        XCTAssertFalse(history.contains { $0.id == writing.id }, "a blank sibling would read as a message to answer")
    }

    func testTheInstructionAsksForTheRestAndNotForARepeat() {
        let node = answer(state: .cancelled)
        let instruction = ChatContinuation.instruction(for: node)
        XCTAssertTrue(instruction.lowercased().contains("do not repeat"))
        XCTAssertFalse(instruction.isEmpty)
    }
}
