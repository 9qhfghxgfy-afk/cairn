import XCTest
@testable import CairnChatDomain

/// The OpenAI-compatible side, read back with this app's own OpenAI client decoder — the same
/// argument as the Ollama suite: the shape this phone writes is the shape this phone reads.
final class ShareOpenAIEncoderTests: XCTestCase {

    private let created = 1_763_000_000
    private let id = "chatcmpl-cairn-test"

    private func events(_ payload: String) throws -> [OpenAICodec.Event] {
        try OpenAICodec.decodeSSEPayload(payload)
    }

    private func payload(of frame: String) -> String {
        let prefix = "data: "
        XCTAssertTrue(frame.hasPrefix(prefix), "an SSE event is a data line: \(frame)")
        XCTAssertTrue(frame.hasSuffix("\n\n"), "and a blank line ends it")
        return String(frame.dropFirst(prefix.count).dropLast(2))
    }

    func testTheModelListDecodesAsAListing() throws {
        let entries = [ShareModelEntry(id: "ondevice-apple", displayName: "Apple model", engineID: "ondevice-apple")]
        let body = ShareOpenAIEncoder.modelListBody(entries, created: created)
        let models = try OpenAICodec.decodeModels(Data(body.utf8), providerID: "share")
        XCTAssertEqual(models.map(\.id), ["ondevice-apple"])
    }

    func testChunksDecodeAsDeltasInOrder() throws {
        let first = payload(of: ShareFrame.sse(ShareOpenAIEncoder.contentChunk(id: id, created: created, model: "m", text: "Hello")))
        let second = payload(of: ShareFrame.sse(ShareOpenAIEncoder.contentChunk(id: id, created: created, model: "m", text: " world")))
        XCTAssertEqual(try events(first), [.content("Hello")])
        XCTAssertEqual(try events(second), [.content(" world")])
    }

    /// Reasoning is written only when an engine really produced it, under the field a reasoning
    /// server uses — so the decoder has to read it back as thinking, not as content.
    func testAReasoningChunkArrivesAsReasoning() throws {
        let frame = payload(of: ShareFrame.sse(ShareOpenAIEncoder.reasoningChunk(id: id, created: created, model: "m", text: "pondering")))
        XCTAssertEqual(try events(frame), [.thinking("pondering")])
    }

    func testTheFinishChunkAndTheDoneSentinelDecodeAsTheEndOfATurn() throws {
        let finish = payload(of: ShareFrame.sse(ShareOpenAIEncoder.finishChunk(id: id, created: created, model: "m", reason: .stop)))
        XCTAssertEqual(try events(finish), [.finished(.stop)])
        XCTAssertEqual(ShareFrame.sseDone, "data: [DONE]\n\n")
        let sentinel = String(ShareFrame.sseDone.dropFirst("data: ".count).dropLast(2))
        XCTAssertEqual(try events(sentinel), [.streamDone])
    }

    func testANonStreamedAnswerCarriesTheMessageAndTheUsage() throws {
        let body = ShareOpenAIEncoder.answerBody(id: id, created: created, model: "m", text: "Whole.", reason: .length, completionTokens: 5, promptTokens: 11)
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)), let object = root.dictionaryValue else {
            return XCTFail("the answer body is JSON")
        }
        XCTAssertEqual(object["object"]?.textValue, "chat.completion")
        let choice = object["choices"]?.arrayValue?.first?.dictionaryValue
        XCTAssertEqual(choice?["message"]?.dictionaryValue?["content"]?.textValue, "Whole.")
        XCTAssertEqual(choice?["finish_reason"]?.textValue, "length")
        let usage = object["usage"]?.dictionaryValue
        XCTAssertEqual(usage?["completion_tokens"]?.intValue, 5)
        XCTAssertEqual(usage?["prompt_tokens"]?.intValue, 11)
        XCTAssertEqual(usage?["total_tokens"]?.intValue, 16, "the total is the sum, not a guess")
    }

    func testAwkwardTextSurvivesTheEncode() throws {
        let awkward = "one\n\"two\" \\ three"
        let frame = payload(of: ShareFrame.sse(ShareOpenAIEncoder.contentChunk(id: id, created: created, model: "m", text: awkward)))
        XCTAssertEqual(try events(frame), [.content(awkward)])
    }

    func testATurnIdIsCorrelatedAndCairnsOwn() {
        let produced = ShareOpenAIEncoder.turnID()
        XCTAssertTrue(produced.hasPrefix("chatcmpl-cairn-"))
        XCTAssertNotEqual(produced, ShareOpenAIEncoder.turnID())
    }

    func testFinishReasonsSayWhatActuallyHappened() {
        XCTAssertEqual(ShareOpenAIEncoder.finishReasonName(.stop), "stop")
        XCTAssertEqual(ShareOpenAIEncoder.finishReasonName(.length), "length")
        XCTAssertEqual(ShareOpenAIEncoder.finishReasonName(.contentFilter), "content_filter")
        XCTAssertEqual(ShareOpenAIEncoder.finishReasonName(.cancelled), "cancelled")
    }
}
