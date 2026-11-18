import XCTest
@testable import CairnChatDomain

final class OpenAICodecTests: XCTestCase {

    private func request() -> GenerationRequest {
        GenerationRequest(
            modelID: "some-model",
            messages: [
                ChatMessagePayload(role: .system, text: "sys"),
                ChatMessagePayload(role: .user, text: "hi"),
            ],
            config: ChatConfig(
                persona: "sys",
                sampling: SamplingConfig(temperature: 0.5, topP: 0.9, maxTokens: 256)
            )
        )
    }

    /// The OpenAI schema's own surface, read from the kind rather than hardcoded here: this is the
    /// table the wire uses, so the test proves the filter rather than restating it.
    private var openAISupport: SamplingSupport { ServerProfileKind.openAICompatible.samplingSupport }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func testRequestBodyShape() throws {
        let body = try jsonObject(
            OpenAICodec.chatRequestBody(request(), support: openAISupport)
        )
        XCTAssertEqual(body["model"] as? String, "some-model")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 256)
        XCTAssertEqual(body["temperature"] as? Double, 0.5)
        XCTAssertEqual(body["top_p"] as? Double, 0.9)
        let streamOptions = body["stream_options"] as? [String: Any]
        XCTAssertEqual(streamOptions?["include_usage"] as? Bool, true)
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.first?["role"] as? String, "system")
        XCTAssertEqual(messages?.first?["content"] as? String, "sys")
        XCTAssertEqual(messages?.last?["content"] as? String, "hi",
                       "text-only turns must use the plain string content form")
    }

    /// The other half of the duplicate-system-message bug: this encoder used to prepend its own
    /// system message on top of the one already in `messages`.
    func testEncoderInventsNoSystemMessage() throws {
        var withoutSystem = request()
        withoutSystem.messages.removeFirst()
        let body = try jsonObject(
            OpenAICodec.chatRequestBody(withoutSystem, support: openAISupport)
        )
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
    }

    /// A knob the user configured that the OpenAI schema does not document is **not sent**. These
    /// servers accept an unknown key and then ignore it, which would leave the user believing a knob
    /// is live. Ollama documents the same knobs, so the same configuration must send them there.
    func testUnsupportedKnobsAreNeverSentToAnOpenAIServer() throws {
        let configured = GenerationRequest(
            modelID: "some-model",
            messages: [ChatMessagePayload(role: .user, text: "hi")],
            config: ChatConfig(sampling: SamplingConfig(
                temperature: 0.4, minP: 0.05, topK: 20, repeatPenalty: 1.3, contextWindow: 16384
            ))
        )
        let openAI = try jsonObject(
            OpenAICodec.chatRequestBody(configured, support: openAISupport)
        )
        XCTAssertEqual(openAI["temperature"] as? Double, 0.4)
        for key in ["min_p", "top_k", "repeat_penalty", "num_ctx", "num_predict", "context_window"] {
            XCTAssertNil(openAI[key], "\(key) is not part of the OpenAI schema and must not be sent")
        }

        let ollama = try jsonObject(
            OllamaCodec.chatRequestBody(configured, support: ServerProfileKind.ollama.samplingSupport)
        )
        let options = ollama["options"] as? [String: Any]
        XCTAssertEqual(options?["min_p"] as? Double, 0.05)
        XCTAssertEqual(options?["top_k"] as? Int, 20)
        XCTAssertEqual(options?["repeat_penalty"] as? Double, 1.3)
        XCTAssertEqual(options?["num_ctx"] as? Int, 16384)
    }

    func testUsageCanBeTurnedOff() throws {
        let body = try jsonObject(
            OpenAICodec.chatRequestBody(request(), support: openAISupport, includeUsage: false)
        )
        XCTAssertNil(body["stream_options"],
                     "retries after a rejection must omit stream_options entirely")
    }

    func testVisionPartsShape() throws {
        let withImage = GenerationRequest(
            modelID: "vision-model",
            messages: [ChatMessagePayload(role: .user, text: "look",
                                          imageData: [Data([7, 8])])],
            config: .bare
        )
        let body = try jsonObject(
            OpenAICodec.chatRequestBody(
                withImage, support: openAISupport, modelSupportsVision: true
            )
        )
        let messages = body["messages"] as? [[String: Any]]
        let content = messages?.last?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2)
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.last?["type"] as? String, "image_url")
        let imageURL = content?.last?["image_url"] as? [String: Any]
        XCTAssertEqual(imageURL?["url"] as? String,
                       "data:image/jpeg;base64,\(Data([7, 8]).base64EncodedString())")
    }

    func testSSELineExtraction() {
        XCTAssertEqual(OpenAICodec.sseDataPayload(fromLine: "data: hello"), "hello")
        XCTAssertEqual(OpenAICodec.sseDataPayload(fromLine: "data:hello"), "hello")
        XCTAssertNil(OpenAICodec.sseDataPayload(fromLine: ": keep-alive comment"))
        XCTAssertNil(OpenAICodec.sseDataPayload(fromLine: "event: message"))
        XCTAssertNil(OpenAICodec.sseDataPayload(fromLine: ""))
    }

    func testSSEEvents() throws {
        XCTAssertEqual(
            try OpenAICodec.decodeSSEPayload("[DONE]"),
            [.streamDone]
        )
        XCTAssertEqual(
            try OpenAICodec.decodeSSEPayload(
                #"{"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}"#),
            [.content("Hel")]
        )
        XCTAssertEqual(
            try OpenAICodec.decodeSSEPayload(
                #"{"choices":[{"delta":{"reasoning_content":"think","content":"t"},"finish_reason":null}]}"#),
            [.thinking("think"), .content("t")]
        )
        XCTAssertEqual(
            try OpenAICodec.decodeSSEPayload(
                #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#),
            [.finished(.stop)]
        )
        XCTAssertEqual(
            try OpenAICodec.decodeSSEPayload(
                #"{"choices":[],"usage":{"prompt_tokens":11,"completion_tokens":42}}"#),
            [.usage(promptTokens: 11, completionTokens: 42)]
        )
        XCTAssertEqual(
            try OpenAICodec.decodeSSEPayload(#"{"error":{"message":"bad key"}}"#),
            [.error("bad key")]
        )
        XCTAssertEqual(try OpenAICodec.decodeSSEPayload(""), [])
    }

    func testMalformedSSEThrowsTypedError() {
        XCTAssertThrowsError(try OpenAICodec.decodeSSEPayload("not json")) { error in
            XCTAssertEqual(error as? OpenAICodec.CodecError, .malformedPayload)
        }
    }

    func testFinishReasonMapping() {
        XCTAssertEqual(OpenAICodec.finishReason(from: "stop"), .stop)
        XCTAssertEqual(OpenAICodec.finishReason(from: "length"), .length)
        XCTAssertEqual(OpenAICodec.finishReason(from: "content_filter"), .contentFilter)
        XCTAssertEqual(OpenAICodec.finishReason(from: "whatever"), .unknown)
        XCTAssertEqual(OpenAICodec.finishReason(from: nil), .unknown)
    }

    func testMetricsOnlyWithRealUsage() {
        let metrics = OpenAICodec.metrics(promptTokens: 11, completionTokens: 42,
                                          elapsedSeconds: 2, timeToFirstTokenSeconds: 0.1,
                                          finishReason: .stop)
        XCTAssertEqual(metrics?.tokensGenerated, 42)
        XCTAssertEqual(metrics?.promptTokens, 11)
        XCTAssertNil(
            OpenAICodec.metrics(promptTokens: 5, completionTokens: nil,
                                elapsedSeconds: 1, timeToFirstTokenSeconds: nil,
                                finishReason: .stop),
            "no usage chunk means no metrics — never estimated"
        )
    }

    func testModelListDecoding() throws {
        let models = try OpenAICodec.decodeModels(
            Data(#"{"data":[{"id":"a"},{"id":"b"}]}"#.utf8), providerID: "p"
        )
        XCTAssertEqual(models.map(\.id), ["a", "b"])
        XCTAssertEqual(models.first?.providerID, "p")
        XCTAssertEqual(models.first?.supportsThinking, false)
    }

    /// End-to-end: an SSE body chopped one byte at a time still produces the
    /// exact answer, the thinking gate, one finish, and real usage.
    func testFuzzByteByByteStream() throws {
        let body = """
        : keep-alive

        data: {"choices":[{"delta":{"reasoning_content":"mm"}}]}

        data: {"choices":[{"delta":{"content":"He"}}]}
        data: {"choices":[{"delta":{"content":"y"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}
        data: {"usage":{"prompt_tokens":3,"completion_tokens":2}}
        data: [DONE]

        """
        var parser = LineStreamParser()
        var text = ""
        var thinking = ""
        var finish: FinishReason?
        var usage: (Int?, Int?)?
        for byte in Data(body.utf8) {
            for lineData in parser.feed(Data([byte])) {
                guard let line = LineStreamParser.decode(lineData),
                      let payload = OpenAICodec.sseDataPayload(fromLine: line)
                else { continue }
                for event in try OpenAICodec.decodeSSEPayload(payload) {
                    switch event {
                    case .content(let t): text += t
                    case .thinking(let t): thinking += t
                    case .finished(let reason): finish = reason
                    case .usage(let p, let c): usage = (p, c)
                    case .streamDone: break
                    // A text-only stream must not yield call fragments; stitched calls have their own
                    // suite, and one appearing here would mean the decoder is inventing them.
                    case .toolCallDelta: XCTFail("unexpected call fragment in a text-only stream")
                    case .error: XCTFail("unexpected error event")
                    }
                }
            }
        }
        XCTAssertEqual(text, "Hey")
        XCTAssertEqual(thinking, "mm")
        XCTAssertEqual(finish, .stop)
        XCTAssertEqual(usage?.0, 3)
        XCTAssertEqual(usage?.1, 2)
    }
}