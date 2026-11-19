import XCTest
@testable import CairnChatDomain

/// One turn run end to end against a recorder, so the head-first rule, the closing frame, and what
/// a failure look like on the wire are all proved without a listener.
final class ShareTurnPumpTests: XCTestCase {
    private struct Boom: Error { var description: String { "boom-secret" } }

    private struct StubEngine: InferenceProvider {
        var chunks: [StreamChunk]
        var fails: Bool = false
        let id: String
        let displayName: String
        var networkClass: NetworkClass { .onDevice }
        var capabilities: ProviderCapabilities { ProviderCapabilities() }
        var serverProfileID: UUID? { nil }
        func models() async throws -> [ModelInfo] { [] }

        func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
            let chunks = self.chunks
            let fails = self.fails
            return AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                if fails { continuation.finish(throwing: Boom()) } else { continuation.finish() }
            }
        }
    }

    private actor Sink: ShareFrameWriting {
        private(set) var head: ShareReply?
        private(set) var frames: [String] = []
        private(set) var finished = false
        func writeReply(_ reply: ShareReply) async { head = reply }
        func writeFrame(_ frame: String) async { frames.append(frame) }
        func finishWriting() async { finished = true }
    }

    private func turnBody(_ extra: String = "") -> ShareTurnRequest {
        ShareTurnRequest(
            modelID: "m",
            messages: [ChatMessagePayload(role: .user, text: "hi")],
            streams: true,
            endpoint: .chat(dialect: .ollama)
        )
    }

    func testAStreamingTurnWritesTheHeadBeforeTheFirstToken() async {
        let sink = Sink()
        let engine = StubEngine(chunks: [.content("Hello "), .content("there")], id: "m", displayName: "M")
        let reason = await ShareTurnPump.run(turn: turnBody(), provider: engine, to: sink)
        let head = await sink.head
        let frames = await sink.frames
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(head?.streaming, true)
        XCTAssertEqual(head?.contentType, "application/x-ndjson")
        XCTAssertEqual(frames.count, 3, "two content frames and a closing frame")
        XCTAssertTrue(frames.last?.contains("\"done\":true") == true)
        let streamFinished = await sink.finished
        XCTAssertTrue(streamFinished)
    }

    func testANonStreamingTurnWritesOneWholeAnswerAndNoFrames() async throws {
        let sink = Sink()
        var turn = turnBody()
        turn.streams = false
        let engine = StubEngine(chunks: [.content("Whole "), .content("answer"),
                                         .metrics(GenerationMetrics(tokensGenerated: 2, promptTokens: 5, elapsedSeconds: 0.2, timeToFirstTokenSeconds: nil, finishReason: .stop))],
                                id: "m", displayName: "M")
        let reason = await ShareTurnPump.run(turn: turn, provider: engine, to: sink)
        let head = await sink.head
        let frames = await sink.frames
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(frames, [], "a whole answer arrives as one body, not as frames")
        XCTAssertEqual(head?.streaming, false)
        let events = try OllamaCodec.decodeNDJSONLine(head?.bodyData ?? Data())
        XCTAssertEqual(events.first, .content("Whole answer"))
    }

    /// A turn that died part-way must not look like an answer that simply stopped early: the client
    /// gets its own error shape, and the engine's failure text never rides along to a stranger.
    func testAFailedStreamSaysSoInTheDialectsOwnShapeAndLeaksNothing() async {
        let sink = Sink()
        let engine = StubEngine(chunks: [.content("partial")], fails: true, id: "m", displayName: "M")
        let reason = await ShareTurnPump.run(turn: turnBody(), provider: engine, to: sink)
        let frames = await sink.frames
        let text = frames.joined()
        XCTAssertEqual(reason, .error)
        XCTAssertTrue(text.contains(ShareTurnPump.failureText))
        XCTAssertFalse(text.contains("boom-secret"), "what the engine threw is not written to a client")
        let closedAfterFailure = await sink.finished
        XCTAssertTrue(closedAfterFailure, "a failed turn still closes, or the client waits forever")
    }

    func testAFailedWholeAnswerIsAFailedStatusNotAnEmptyOne() async {
        let sink = Sink()
        var turn = turnBody()
        turn.streams = false
        let engine = StubEngine(chunks: [], fails: true, id: "m", displayName: "M")
        let reason = await ShareTurnPump.run(turn: turn, provider: engine, to: sink)
        let head = await sink.head
        XCTAssertEqual(reason, .error)
        XCTAssertEqual(head?.status, 500)
        XCTAssertFalse(String(decoding: head?.bodyData ?? Data(), as: UTF8.self).contains("boom-secret"))
    }

    func testAnOpenAIStreamEndsWithTheSentinelEvenWhenTheEngineFails() async {
        let sink = Sink()
        let turn = ShareTurnRequest(
            modelID: "m",
            messages: [ChatMessagePayload(role: .user, text: "hi")],
            streams: true,
            endpoint: .chat(dialect: .openAI)
        )
        let engine = StubEngine(chunks: [.content("partial")], fails: true, id: "m", displayName: "M")
        _ = await ShareTurnPump.run(turn: turn, provider: engine, to: sink)
        let frames = await sink.frames
        XCTAssertEqual(frames.last, ShareFrame.sseDone, "an OpenAI client reads the sentinel, even on failure")
    }
}
