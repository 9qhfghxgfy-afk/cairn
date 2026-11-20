import XCTest
@testable import CairnChatDomain

/// Fitting a turn to an engine that states how much it holds.
///
/// Apple's system model holds roughly 4,096 tokens of instructions, history and answer together, and
/// a prompt one exchange too long does not degrade — the whole turn fails, with a framework error
/// that says nothing a person can act on. So the fit is decided here, in the open, and proved: the
/// oldest turns go first, the tool block goes next, and a question that cannot fit alone is refused
/// with a reason instead of being sent and rejected.
final class PromptContextFitTests: XCTestCase {
    func testCeilingReservesRoomForTheAnswer() {
        // 4,096 tokens less a 512-token reserve, at four characters to a token.
        XCTAssertEqual(PromptContextFit.characterCeiling(tokenCeiling: 4096), 14_336)
        // A ceiling at or below the reserve fits nothing; it does not go negative and silently accept
        // an empty prompt.
        XCTAssertEqual(PromptContextFit.characterCeiling(tokenCeiling: 512), 0)
        XCTAssertEqual(PromptContextFit.characterCeiling(tokenCeiling: 128), 0)
    }

    func testAShortTurnIsPassedThroughUnchanged() {
        let fitted = PromptContextFit.fit(
            systemText: "You are Cairn.",
            body: "user: hi\n\nassistant: hello",
            tokenCeiling: 4096
        )
        XCTAssertTrue(fitted.fits)
        XCTAssertEqual(fitted.instructions, "You are Cairn.")
        XCTAssertEqual(fitted.body, "user: hi\n\nassistant: hello")
        XCTAssertEqual(fitted.droppedTurnCount, 0)
        XCTAssertFalse(fitted.droppedToolBlock)
    }

    func testTheOldestTurnsGoFirstAndTheQuestionJustAskedSurvives() {
        let body = "user: oldest thing ever said\n\nassistant: long ago\n\nuser: what is 2 + 2?"
        let fitted = PromptContextFit.fit(
            systemText: nil,
            body: body,
            tokenCeiling: 520
        )
        XCTAssertEqual(fitted.droppedTurnCount, 2)
        XCTAssertEqual(fitted.body, "user: what is 2 + 2?")
        XCTAssertTrue(fitted.fits)
    }

    func testTheToolBlockGoesBeforeTheLastQuestion() {
        let toolBlock = "\n\nTools: [calculator]{\"name\":\"calculator\"}"
        let instructions = "You are Cairn." + toolBlock
        let fitted = PromptContextFit.fit(
            systemText: instructions,
            body: "user: what is 2 + 2?",
            toolBlock: toolBlock,
            tokenCeiling: 528
        )
        XCTAssertTrue(fitted.droppedToolBlock)
        XCTAssertEqual(fitted.instructions, "You are Cairn.")
        XCTAssertTrue(fitted.fits)
        // Losing the block costs the turn its tools; it must not silently leave the block in place.
        XCTAssertFalse(fitted.instructions.contains("calculator"))
    }

    func testHistoryIsDroppedBeforeTheToolBlockIsTouched() {
        let toolBlock = "\n\nTools: [calculator]"
        let instructions = "You are Cairn." + toolBlock
        let fitted = PromptContextFit.fit(
            systemText: instructions,
            body: "user: old question\n\nassistant: old answer\n\nuser: new question",
            toolBlock: toolBlock,
            tokenCeiling: 532
        )
        XCTAssertGreaterThan(fitted.droppedTurnCount, 0)
        XCTAssertFalse(fitted.droppedToolBlock, "the block is the last thing to go")
    }

    /// A question alone larger than the window is not trimmed to nothing and sent anyway. It is
    /// refused, with the reason, so the composer can say what happened.
    func testATurnThatCannotFitIsRefusedRatherThanSent() {
        let huge = String(repeating: "word ", count: 5_000)
        let fitted = PromptContextFit.fit(
            systemText: nil,
            body: "user: \(huge)",
            tokenCeiling: 128
        )
        XCTAssertFalse(fitted.fits)
        XCTAssertEqual(fitted.droppedTurnCount, 0, "there was nothing to drop")
    }

    func testStrippingTheBlockLeavesNoStraySeparator() {
        let toolBlock = "\n\nTools: [calculator]"
        let fitted = PromptContextFit.fit(
            systemText: "You are Cairn." + toolBlock,
            body: "user: hi",
            toolBlock: toolBlock,
            tokenCeiling: 12
        )
        XCTAssertTrue(fitted.droppedToolBlock)
        XCTAssertEqual(fitted.instructions, "You are Cairn.")
    }

    /// A block the system text does not actually end with is left alone: the fitter subtracts, it does
    /// not guess at how the block was worded and chew up someone's instructions.
    func testABlockThatIsNotAtTheEndIsNotStripped() {
        let fitted = PromptContextFit.fit(
            systemText: "You are Cairn.",
            body: "user: hi",
            toolBlock: "\n\nTools: [calculator]",
            tokenCeiling: 12
        )
        XCTAssertFalse(fitted.droppedToolBlock)
        XCTAssertFalse(fitted.fits)
    }
}
