import XCTest
@testable import CairnChatDomain

/// The Ollama side of the share surface, read back with this app's own Ollama **client** decoder.
///
/// That is the proof this milestone owes: if Cairn's own reader of `/api/chat` can consume what
/// Cairn's `/api/chat` writes, then the frames are the published shape and not an approximation of
/// it. A test that only string-matched its own output would prove nothing about the wire.
final class ShareOllamaEncoderTests: XCTestCase {

    private let created = "2026-11-18T09:00:00Z"

    private func events(_ frame: String) throws -> [OllamaCodec.Event] {
        try OllamaCodec.decodeNDJSONLine(Data(frame.utf8))
    }

    func testTheVersionNamesCairnRatherThanAnOllamaBuild() throws {
        let body = ShareOllamaEncoder.versionBody()
        XCTAssertEqual(try OllamaCodec.decodeVersion(Data(body.utf8)), ShareSettings.servedVersion)
        XCTAssertTrue(ShareSettings.servedVersion.hasPrefix("cairn"), "a client must not be told this is a desktop Ollama")
    }

    func testTheModelListDecodesAsAModelList() throws {
        let entries = [
            ShareModelEntry(id: "ondevice-apple", displayName: "Apple model", engineID: "ondevice-apple", parameterSize: "3B", quantization: nil),
            ShareModelEntry(id: "ollama-box", displayName: "LAN box", engineID: "ollama-box"),
        ]
        let models = try OllamaCodec.decodeModelList(Data(ShareOllamaEncoder.modelListBody(entries).utf8), providerID: "share")
        XCTAssertEqual(models.map(\.id), ["ondevice-apple", "ollama-box"], "selection order is kept")
        XCTAssertEqual(models[0].parameterSize, "3B")
        XCTAssertNil(models[1].parameterSize, "nothing is invented about an engine that says nothing")
    }

    func testContentAndThinkingFramesDecodeAsTheyWereEmitted() throws {
        XCTAssertEqual(
            try events(ShareOllamaEncoder.contentFrame(model: "box", createdAt: created, text: "Hello ")),
            [.content("Hello ")]
        )
        XCTAssertEqual(
            try events(ShareOllamaEncoder.thinkingFrame(model: "box", createdAt: created, text: "thinking")),
            [.thinking("thinking")]
        )
    }

    func testTheFinalFrameCarriesTheMeasuredCountsAndTheReason() throws {
        let frame = ShareOllamaEncoder.finalFrame(model: "box", createdAt: created, reason: .stop, evalCount: 7, evalDurationMicros: 1_400_000, promptEvalCount: 21)
        XCTAssertEqual(
            try events(frame),
            [.finished(OllamaCodec.FinalInfo(evalCount: 7, evalDurationMicros: 1_400_000, promptEvalCount: 21, doneReason: "stop"))]
        )
    }

    func testANonStreamedAnswerIsOneWholeObject() throws {
        let body = ShareOllamaEncoder.answerBody(model: "box", createdAt: created, text: "A whole answer.", reason: .length, evalCount: 4, evalDurationMicros: 900_000, promptEvalCount: nil)
        let decoded = try events(body)
        XCTAssertEqual(decoded, [.content("A whole answer."), .finished(OllamaCodec.FinalInfo(evalCount: 4, evalDurationMicros: 900_000, doneReason: "length"))])
    }

    /// Text that contains the characters JSON is made of must survive the trip, because model
    /// output is full of them and a hand-built body would break on the first quote.
    func testAwkwardTextSurvivesTheEncode() throws {
        let awkward = "line one\n\"quoted\" \\ backslash\ttab"
        XCTAssertEqual(try events(ShareOllamaEncoder.contentFrame(model: "m", createdAt: created, text: awkward)), [.content(awkward)])
        let answer = ShareOllamaEncoder.answerBody(model: "m", createdAt: created, text: awkward, reason: .stop, evalCount: 1, evalDurationMicros: 1, promptEvalCount: 1)
        XCTAssertEqual(try events(answer).first, .content(awkward))
    }

    func testDoneReasonsSayWhatActuallyHappened() {
        XCTAssertEqual(ShareOllamaEncoder.doneReason(.stop), "stop")
        XCTAssertEqual(ShareOllamaEncoder.doneReason(.length), "length")
        XCTAssertEqual(ShareOllamaEncoder.doneReason(.cancelled), "cancelled", "a stopped turn is not a finished one")
        XCTAssertEqual(ShareOllamaEncoder.doneReason(.error), "error")
    }

    func testNDJSONFramesAreOneObjectPerLine() {
        let frame = ShareFrame.ndjson(ShareOllamaEncoder.contentFrame(model: "m", createdAt: created, text: "hi"))
        XCTAssertTrue(frame.hasSuffix("\n"))
        XCTAssertEqual(frame.filter { $0 == "\n" }.count, 1, "one object, one newline, no blank line")
    }
}
