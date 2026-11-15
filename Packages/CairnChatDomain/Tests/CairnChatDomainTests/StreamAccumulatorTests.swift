import XCTest
@testable import CairnChatDomain

final class StreamAccumulatorTests: XCTestCase {

    func testPhaseTracksThinkingThenContent() {
        var acc = StreamAccumulator()
        XCTAssertEqual(acc.phase, .idle)
        XCTAssertFalse(acc.hasReasoning, "no panel until a provider actually emits reasoning")

        acc.begin()
        XCTAssertEqual(acc.phase, .preparing)

        acc.consume(.thinking("weighing options "))
        XCTAssertEqual(acc.phase, .thinking)
        XCTAssertTrue(acc.hasReasoning)
        XCTAssertEqual(acc.thinking, "weighing options ")

        acc.consume(.thinking("and answering."))
        XCTAssertEqual(acc.thinking, "weighing options and answering.")

        acc.consume(.content("Hel"))
        XCTAssertEqual(acc.phase, .streaming)
        acc.consume(.content("lo."))
        XCTAssertEqual(acc.text, "Hello.")

        acc.consume(.metrics(GenerationMetrics(tokensGenerated: 2, elapsedSeconds: 1.0, finishReason: .stop)))
        XCTAssertEqual(acc.metrics?.tokensPerSecond, 2.0)

        acc.complete()
        XCTAssertEqual(acc.phase, .completed)
        XCTAssertEqual(acc.nodeState, .complete)
    }

    func testThinkingOnlyPanelIsDrivenByActualThinkingChunks() {
        var plain = StreamAccumulator()
        plain.begin()
        plain.consume(.content("no reasoning backend here"))
        XCTAssertFalse(plain.hasReasoning, "a backend with no thinking field must not show a reasoning panel")

        var tagged = StreamAccumulator()
        tagged.begin()
        tagged.consume(.thinking("planning"))
        XCTAssertTrue(tagged.hasReasoning)
    }

    func testCancellationOnlyAppliesToActivePhasesAndKeepsPartialText() {
        var acc = StreamAccumulator()
        acc.begin()
        acc.consume(.content("partial "))
        acc.consume(.content("answer"))
        acc.requestCancellation()
        XCTAssertEqual(acc.phase, .cancelling)
        XCTAssertEqual(acc.text, "partial answer", "cancelling must not discard generated text")

        acc.finishCancelled()
        XCTAssertEqual(acc.phase, .cancelled)
        XCTAssertEqual(acc.nodeState, .cancelled)

        // A completed turn cannot be dragged back into a cancelling state.
        var done = StreamAccumulator()
        done.begin()
        done.consume(.content("finished"))
        done.complete()
        done.requestCancellation()
        XCTAssertEqual(done.phase, .completed)
    }

    func testFailureKeepsWhatWasAlreadyProduced() {
        var acc = StreamAccumulator()
        acc.begin()
        acc.consume(.content("some "))
        acc.fail("connection dropped")
        XCTAssertEqual(acc.phase, .failed)
        XCTAssertEqual(acc.nodeState, .failed)
        XCTAssertEqual(acc.text, "some ")
        XCTAssertEqual(acc.failure, "connection dropped")
    }

    func testToolCallsAreCollectedWithoutReorderingContent() {
        var acc = StreamAccumulator()
        acc.begin()
        acc.consume(.content("before "))
        acc.consume(.toolCall(ToolCallRequest(id: "c1", name: "web_search", argumentsJSON: "{\"q\":\"x\"}")))
        acc.consume(.content("after"))
        XCTAssertEqual(acc.text, "before after")
        XCTAssertEqual(acc.toolCalls.count, 1)
        XCTAssertEqual(acc.toolCalls.first?.name, "web_search")
    }

    func testMetricsNeverInventNumbers() {
        let none = GenerationMetrics(tokensGenerated: 0, elapsedSeconds: 0)
        XCTAssertNil(none.tokensPerSecond, "0 tokens over 0 seconds is not a rate")

        let partial = GenerationMetrics(tokensGenerated: 10, elapsedSeconds: 2.5)
        XCTAssertEqual(partial.tokensPerSecond ?? 0, 4.0, accuracy: 0.0001)
        XCTAssertNil(partial.promptTokens, "unknown prompt tokens stay nil instead of being guessed")
    }
}
