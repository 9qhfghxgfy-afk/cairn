import CairnChatDomain
import Foundation
import Testing

@testable import CairnInferenceNative

// Tags are built by concatenation, as everywhere in this suite: a literal tag in a source file collides
// with the reasoning control token of the toolchain that reads this code.
private let openThink = "<" + "think" + ">"
private let closeThink = "</" + "think" + ">"

/// Counts how often the runtime's first answer token arrived, under the same lock the bridge uses.
private final class MarkCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() {
        lock.lock(); value += 1; lock.unlock()
    }
    var count: Int {
        lock.lock(); defer { lock.unlock() }; return value
    }
}

/// The token callback's own contract: order kept, nothing emitted after a stop, and the "this model is
/// resident" mark fired exactly once, at the first token that really answered.
struct MLXStreamBridgeTests {

    /// Feeds a bridge through its whole turn and hands back everything the stream released.
    private func drained(_ feed: (MLXStreamBridge) -> Void) async throws -> [StreamChunk] {
        var received: [StreamChunk] = []
        let stream = AsyncThrowingStream<StreamChunk, any Error> { continuation in
            feed(MLXStreamBridge(parser: DeviceTemplateChunkParser(), continuation: continuation))
            continuation.finish()
        }
        for try await chunk in stream { received.append(chunk) }
        return received
    }

    private func text(_ chunks: [StreamChunk]) -> String {
        chunks.reduce(into: "") { total, chunk in
            if case .content(let piece) = chunk { total += piece }
        }
    }

    @Test func plainTokensPassThroughInOrder() async throws {
        // The spaces lead each continuation chunk rather than trail the first one, because a parser that
        // has not seen a real answer token yet trims what it finds at either end of it.
        let out = try await drained { bridge in
            bridge.receive(.content("one"))
            bridge.receive(.content(" two"))
            bridge.receive(.content(" three"))
            bridge.complete()
        }
        #expect(text(out) == "one two three")
    }

    @Test func aMarkerSplitAcrossTokensBecomesOneThinkingChunk() async throws {
        let out = try await drained { bridge in
            bridge.receive(.content("before \(openThink)wh"))
            bridge.receive(.content("y\(closeThink) after"))
            bridge.complete()
        }
        #expect(out.contains(.thinking("why")))
        // The region splices out and the whitespace that framed it closes to one space, so the reader
        // never sees a hole where the model's reasoning was.
        #expect(text(out) == "before after")
    }

    @Test func aNonContentChunkIsForwardedUntouched() async throws {
        // Reasoning and calls arrive already in Cairn's vocabulary. A value the runtime measured or
        // parsed is not something this bridge may re-derive, so it goes out exactly as it came in.
        let call = ToolCallRequest(id: "call-1", name: "web_search", argumentsJSON: #"{"q":"oslo"}"#)
        let out = try await drained { bridge in
            bridge.receive(.thinking("weighing"))
            bridge.receive(.toolCall(call))
            bridge.complete()
        }
        #expect(out == [.thinking("weighing"), .toolCall(call)])
    }

    @Test func completeReleasesWhatTheParserWasStillHolding() async throws {
        // A held-back marker-shaped tail that never resolved was ordinary text after all.
        let out = try await drained { bridge in
            bridge.receive(.content("answer"))
            bridge.receive(.content(" <"))
            bridge.complete()
        }
        #expect(text(out) == "answer <")
    }

    @Test func aCancelledTurnEmitsNothingFurther() async throws {
        var received: [StreamChunk] = []
        let stream = AsyncThrowingStream<StreamChunk, any Error> { continuation in
            let bridge = MLXStreamBridge(parser: DeviceTemplateChunkParser(), continuation: continuation)
            bridge.receive(.content("first"))
            bridge.cancel()
            bridge.receive(.content("second"))
            bridge.complete()
            continuation.finish()
        }
        for try await chunk in stream { received.append(chunk) }
        #expect(received == [.content("first")])
    }

    @Test func theResidentMarkFiresOnceAtTheFirstAnswerToken() async throws {
        let marks = MarkCounter()
        let stream = AsyncThrowingStream<StreamChunk, any Error> { continuation in
            let bridge = MLXStreamBridge(
                parser: DeviceTemplateChunkParser(), continuation: continuation
            ) { marks.add() }
            bridge.receive(.thinking("weighing"))   // not an answer token
            bridge.receive(.content("go"))
            bridge.receive(.content("n"))
            bridge.complete()
            continuation.finish()
        }
        for try await _ in stream {}
        #expect(marks.count == 1)
    }
}
