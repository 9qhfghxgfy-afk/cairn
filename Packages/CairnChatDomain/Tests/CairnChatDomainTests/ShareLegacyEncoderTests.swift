import XCTest
@testable import CairnChatDomain

/// The two completion-shaped endpoints, `/api/generate` and `/v1/completions`, whose text lives
/// somewhere other than the chat field.
///
/// The Ollama half is read back with this app's own Ollama client decoder, which reads both shapes —
/// that is the proof the generate frames are the published shape. The legacy OpenAI half has no
/// reader in this app, because Cairn's client only speaks the chat shape, so it is asserted against
/// the published field names instead.
final class ShareLegacyEncoderTests: XCTestCase {
    private let created = "2026-11-18T09:00:00Z"

    private func json(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    func testGenerateFramesCarryTheAnswerAtTheTopLevel() throws {
        let content = ShareOllamaGenerateEncoder.contentFrame(model: "m", createdAt: created, text: "Hello ")
        XCTAssertEqual(try OllamaCodec.decodeNDJSONLine(Data(content.utf8)), [.content("Hello ")],
                       "this app's own reader must find the answer under `response`")

        let thinking = ShareOllamaGenerateEncoder.thinkingFrame(model: "m", createdAt: created, text: "hmm")
        XCTAssertEqual(try OllamaCodec.decodeNDJSONLine(Data(thinking.utf8)), [.thinking("hmm")])
    }

    func testTheFinalGenerateFrameClosesTheStreamWithCounts() {
        let final = ShareOllamaGenerateEncoder.finalFrame(
            model: "m", createdAt: created, reason: .stop,
            evalCount: 12, evalDurationMicros: 3_400_000, promptEvalCount: 7
        )
        let object = json(final)
        XCTAssertEqual(object?["done"] as? Bool, true)
        XCTAssertEqual(object?["done_reason"] as? String, "stop")
        XCTAssertEqual(object?["eval_count"] as? Int, 12)
        XCTAssertEqual(object?["response"] as? String, "", "a closing frame carries an empty answer, not an invented one")
    }

    func testAWholeGenerateAnswerIsOneDoneObject() throws {
        let body = ShareOllamaGenerateEncoder.answerBody(
            model: "m", createdAt: created, text: "Whole answer", reason: .stop,
            evalCount: 3, evalDurationMicros: 1_000_000, promptEvalCount: nil
        )
        XCTAssertEqual(
            try OllamaCodec.decodeNDJSONLine(Data(body.utf8)),
            [.content("Whole answer"),
             .finished(OllamaCodec.FinalInfo(evalCount: 3, evalDurationMicros: 1_000_000, promptEvalCount: nil, doneReason: "stop"))]
        )
        XCTAssertEqual(json(body)?["done"] as? Bool, true)
    }

    func testALegacyCompletionChunkPutsTheTextInChoicesText() {
        let chunk = ShareOpenAICompletionEncoder.textChunk(id: "cmpl-1", created: 1_700_000_000, model: "m", text: "Hi")
        let object = json(chunk)
        XCTAssertEqual(object?["object"] as? String, "text_completion")
        let choice = (object?["choices"] as? [[String: Any]])?.first
        XCTAssertEqual(choice?["text"] as? String, "Hi")
        XCTAssertNil(choice?["delta"], "a completions client is not a chat client")
    }

    func testALegacyCompletionFinishChunkNamesTheReasonAndNoText() {
        let chunk = ShareOpenAICompletionEncoder.finishChunk(id: "cmpl-1", created: 1, model: "m", reason: .length)
        let choice = (json(chunk)?["choices"] as? [[String: Any]])?.first
        XCTAssertEqual(choice?["finish_reason"] as? String, "length")
        XCTAssertNil(choice?["text"])
    }
}
