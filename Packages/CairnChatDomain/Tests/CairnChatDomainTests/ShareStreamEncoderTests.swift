import XCTest
@testable import CairnChatDomain

/// The translation from one engine stream to one published stream.
///
/// Both dialects are read back with this app's own client decoders, so the frames are checked as
/// wire shapes rather than as strings this file also wrote.
final class ShareStreamEncoderTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_763_000_000)

    private func payload(of frame: String) -> String {
        let prefix = "data: "
        XCTAssertTrue(frame.hasPrefix(prefix), "an SSE event is a data line: \(frame)")
        XCTAssertTrue(frame.hasSuffix("\n\n"), "and a blank line ends it")
        return String(frame.dropFirst(prefix.count).dropLast(2))
    }

    func testOllamaContentGoesOutOneLinePerPiece() throws {
        var encoder = ShareStreamEncoder(shape: .ollamaChat, model: "m", started: started)
        var frames: [String] = []
        frames += encoder.append(.content("Hello "))
        frames += encoder.append(.content("there"))
        XCTAssertEqual(frames.count, 2, "each piece is its own frame, so a client reads as it arrives")
        let events = try frames.flatMap { try OllamaCodec.decodeNDJSONLine(Data($0.utf8)) }
        XCTAssertEqual(events, [.content("Hello "), .content("there")])
        XCTAssertTrue(frames.allSatisfy { $0.hasSuffix("\n") }, "NDJSON is one object per line")
    }

    func testTheClosingFrameSaysDoneAndInventsNoCounts() throws {
        var encoder = ShareStreamEncoder(shape: .ollamaChat, model: "m", started: started)
        _ = encoder.append(.content("hi"))
        let closing = encoder.finish(reason: .stop)
        XCTAssertEqual(closing.count, 1, "Ollama ends with a done object, not a sentinel")
        let events = try OllamaCodec.decodeNDJSONLine(Data(closing[0].utf8))
        guard case .finished(let info) = events.first, case .none = events.dropFirst().first else {
            return XCTFail("the closing frame must read as finished: \(events)")
        }
        XCTAssertEqual(info.doneReason, "stop")
        XCTAssertNil(info.evalCount, "a turn that reported no counts is not reported as zero tokens")
    }

    func testCountsAreCopiedFromTheEngineThatMeasuredThem() throws {
        var encoder = ShareStreamEncoder(shape: .ollamaGenerate, model: "m", started: started)
        _ = encoder.append(.content("hi"))
        _ = encoder.append(.metrics(GenerationMetrics(tokensGenerated: 9, promptTokens: 4, elapsedSeconds: 0.5, timeToFirstTokenSeconds: nil, finishReason: .length)))
        let closing = encoder.finish(reason: .stop)
        let events = try OllamaCodec.decodeNDJSONLine(Data(closing[0].utf8))
        guard case .finished(let info) = events.first else { return XCTFail("expected a closing frame") }
        XCTAssertEqual(info.evalCount, 9, "the engine's own count")
        XCTAssertEqual(info.promptEvalCount, 4)
        XCTAssertEqual(info.doneReason, "length", "what the engine reported beats what the caller assumed")
    }

    func testOpenAIContentIsOneSSEEventPerPieceAndEndsWithTheSentinel() throws {
        var encoder = ShareStreamEncoder(shape: .openAIChat, model: "m", started: started)
        var frames: [String] = []
        frames += encoder.append(.content("Hello "))
        frames += encoder.append(.content("there"))
        frames += encoder.finish(reason: .stop)
        let events = try frames.flatMap { try OpenAICodec.decodeSSEPayload(payload(of: $0)) }
        XCTAssertTrue(events.contains(.content("Hello ")))
        XCTAssertEqual(frames.last, ShareFrame.sseDone, "an OpenAI client reads the sentinel, not a closed socket")
        XCTAssertEqual(encoder.wholeText, "Hello there")
    }

    /// Reasoning is forwarded because an engine emitted it, and only then. On the legacy
    /// completions route there is nowhere to put it, so it is dropped rather than pasted into the
    /// answer, which would present a model's private scratch as its reply.
    func testReasoningTravelsWhereTheDialectHasRoomForIt() {
        var chat = ShareStreamEncoder(shape: .openAIChat, model: "m", started: started)
        let frames = chat.append(.thinking("hmm"))
        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(frames[0].contains("reasoning_content"))

        var legacy = ShareStreamEncoder(shape: .openAICompletion, model: "m", started: started)
        XCTAssertTrue(legacy.append(.thinking("hmm")).isEmpty)
        XCTAssertEqual(legacy.wholeText, "", "a dropped reasoning piece never joins the answer")
    }

    func testAToolCallIsNotForwardedToACallerThatWasOfferedNoTools() {
        var encoder = ShareStreamEncoder(shape: .ollamaChat, model: "m", started: started)
        let call = ToolCallRequest(id: "c1", name: "shell", argumentsJSON: "{}")
        XCTAssertTrue(encoder.append(.toolCall(call)).isEmpty)
    }
}
