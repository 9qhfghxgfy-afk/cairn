import XCTest
@testable import CairnChatDomain

final class OllamaCodecTests: XCTestCase {

    private func request() -> GenerationRequest {
        GenerationRequest(
            modelID: "qwen3:8b",
            messages: [
                ChatMessagePayload(role: .system, text: "be brief"),
                ChatMessagePayload(role: .user, text: "hi"),
                ChatMessagePayload(role: .assistant, text: "hello"),
                ChatMessagePayload(role: .user, text: "again"),
            ],
            config: ChatConfig(
                persona: "be brief",
                sampling: SamplingConfig(
                    temperature: 0.5, topP: 0.9, maxTokens: 256, contextWindow: 8192
                )
            )
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func testRequestBodyShape() throws {
        let body = try jsonObject(OllamaCodec.chatRequestBody(request(), support: .all))
        XCTAssertEqual(body["model"] as? String, "qwen3:8b")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["think"], "think must be absent unless the model supports thinking")
        let options = body["options"] as? [String: Any]
        XCTAssertEqual(options?["top_p"] as? Double, 0.9)
        XCTAssertEqual(options?["temperature"] as? Double, 0.5)
        XCTAssertEqual(options?["num_predict"] as? Int, 256)
        XCTAssertEqual(options?["num_ctx"] as? Int, 8192)
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 4, "the assembled system message is carried through")
        XCTAssertEqual(messages?.first?["role"] as? String, "system")
        XCTAssertEqual(messages?.first?["content"] as? String, "be brief")
    }

    /// The duplicate-system-message bug: the tree flattened a system prompt into the messages **and**
    /// the encoder prepended another, so a chat with a persona sent two system messages every turn.
    /// The encoder no longer has a system prompt to add, so a request without one stays without one.
    func testEncoderInventsNoSystemMessage() throws {
        var withoutSystem = request()
        withoutSystem.messages.removeFirst()
        let body = try jsonObject(OllamaCodec.chatRequestBody(withoutSystem, support: .all))
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 3)
        XCTAssertNotEqual(messages?.first?["role"] as? String, "system")
        XCTAssertEqual(messages?.filter { ($0["role"] as? String) == "system" }.count, 0)
    }

    /// Nothing configured means no `options` object at all, not an empty one: an empty object claims
    /// the user asked for something, and a server may read it as a request to reset its own defaults.
    func testNoOptionsWhenNothingIsConfigured() throws {
        let bare = GenerationRequest(
            modelID: "qwen3:8b",
            messages: [ChatMessagePayload(role: .user, text: "hi")],
            config: .bare
        )
        let body = try jsonObject(OllamaCodec.chatRequestBody(bare, support: .all))
        XCTAssertNil(body["options"], "an unset knob must not be sent as a zero or an empty object")
    }

    func testThinkingFlagOnlyWhenSupported() throws {
        let on = try jsonObject(
            OllamaCodec.chatRequestBody(request(), support: .all, thinking: true)
        )
        XCTAssertEqual(on["think"] as? Bool, true)
    }

    func testImagesOnlyForVisionModels() throws {
        let withImage = GenerationRequest(
            modelID: "llava",
            messages: [ChatMessagePayload(role: .user, text: "what?",
                                          imageData: [Data([1, 2, 3])])],
            config: .bare
        )
        let off = try jsonObject(
            OllamaCodec.chatRequestBody(withImage, support: .all)
        )
        let offMessages = off["messages"] as? [[String: Any]]
        XCTAssertNil(offMessages?.last?["images"] as? [String],
                     "images must be omitted for non-vision models")

        let on = try jsonObject(
            OllamaCodec.chatRequestBody(withImage, support: .all, modelSupportsVision: true)
        )
        let onMessages = on["messages"] as? [[String: Any]]
        let images = onMessages?.last?["images"] as? [String]
        XCTAssertEqual(images, [Data([1, 2, 3]).base64EncodedString()])
    }

    func testNDJSONEvents() throws {
        XCTAssertEqual(
            try OllamaCodec.decodeNDJSONLine(
                Data(#"{"model":"m","message":{"role":"assistant","content":"Hel"}}"#.utf8)),
            [.content("Hel")]
        )
        XCTAssertEqual(
            try OllamaCodec.decodeNDJSONLine(
                Data(#"{"message":{"role":"assistant","thinking":"because"}}"#.utf8)),
            [.thinking("because")]
        )
        let doneEvents = try OllamaCodec.decodeNDJSONLine(
            Data(#"{"done":true,"done_reason":"stop","eval_count":42,"eval_duration":21000000,"prompt_eval_count":10}"#.utf8))
        XCTAssertEqual(doneEvents, [
            .finished(OllamaCodec.FinalInfo(evalCount: 42, evalDurationMicros: 21_000_000,
                                            promptEvalCount: 10, doneReason: "stop")),
        ])
        XCTAssertEqual(
            try OllamaCodec.decodeNDJSONLine(Data(#"{"error":"model not found"}"#.utf8)),
            [.error("model not found")]
        )
        XCTAssertEqual(try OllamaCodec.decodeNDJSONLine(Data()), [])
    }

    func testMalformedLineThrowsTypedError() {
        XCTAssertThrowsError(try OllamaCodec.decodeNDJSONLine(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? OllamaCodec.CodecError, .malformedLine)
        }
    }

    func testMetricsOnlyFromRealCounts() {
        let info = OllamaCodec.FinalInfo(evalCount: 42, evalDurationMicros: 21_000_000,
                                         promptEvalCount: 10, doneReason: "stop")
        let metrics = OllamaCodec.metrics(from: info, elapsedSeconds: 2.1,
                                          timeToFirstTokenSeconds: 0.2)
        XCTAssertEqual(metrics?.tokensGenerated, 42)
        XCTAssertEqual(metrics?.promptTokens, 10)
        XCTAssertEqual(metrics?.tokensPerSecond ?? 0, 20, accuracy: 0.01)
        XCTAssertNil(OllamaCodec.metrics(from: .init(), elapsedSeconds: 1,
                                         timeToFirstTokenSeconds: nil),
                     "no server counts means no metrics — never estimated")
    }

    func testModelListDecoding() throws {
        let payload = Data("""
        {"models":[
          {"name":"qwen3:8b","details":{"parameter_size":"8B","quantization_level":"Q4_0","context_length":40960,"supports_thinking":true}},
          {"name":"llava:7b","details":{"projector":"mmproj-f116.gguf"}},
          {"name":"plain"}
        ]}
        """.utf8)
        let models = try OllamaCodec.decodeModelList(payload, providerID: "p1")
        XCTAssertEqual(models.count, 3)
        XCTAssertEqual(models[0].id, "qwen3:8b")
        XCTAssertEqual(models[0].supportsThinking, true)
        XCTAssertEqual(models[0].supportsVision, false)
        XCTAssertEqual(models[0].contextLength, 40960)
        XCTAssertEqual(models[1].supportsVision, true)
        XCTAssertEqual(models[2].supportsVision, false)
        XCTAssertEqual(models[2].supportsThinking, false)
    }

    func testVersionAndNameBodies() throws {
        XCTAssertEqual(try OllamaCodec.decodeVersion(Data(#"{"version":"0.12.6"}"#.utf8)), "0.12.6")
        let pull = try jsonObject(OllamaCodec.nameRequestBody(model: "llama3", stream: false))
        XCTAssertEqual(pull["name"] as? String, "llama3")
        XCTAssertEqual(pull["stream"] as? Bool, false)
    }

    /// Applies one decoded NDJSON line to the accumulators under test.
    private func consume(
        _ line: Data,
        text: inout String,
        thinking: inout String,
        finished: inout OllamaCodec.FinalInfo?
    ) throws {
        for event in try OllamaCodec.decodeNDJSONLine(line) {
            switch event {
            case .content(let t): text += t
            case .thinking(let t): thinking += t
            case .finished(let info): finished = info
            case .error: XCTFail("unexpected error event")
            }
        }
    }

    /// End-to-end: NDJSON split one byte at a time still yields the exact
    /// concatenated answer and exactly one finished event.
    func testFuzzByteByByteStream() throws {
        let body = """
        {"message":{"role":"assistant","thinking":"why"}}
        {"message":{"role":"assistant","content":"A"}}
        {"message":{"role":"assistant","content":"B"}}

        {"done":true,"eval_count":2}
        """
        let data = Data(body.utf8)
        var parser = LineStreamParser()
        var text = ""
        var thinking = ""
        var finished: OllamaCodec.FinalInfo?
        for byte in data {
            for line in parser.feed(Data([byte])) {
                try consume(line, text: &text, thinking: &thinking, finished: &finished)
            }
        }
        // A producer may end without a trailing newline, so the tail still has to be
        // taken from the parser - exactly what the streaming pipeline does.
        if let tail = parser.takeTrailingPartialLine() {
            try consume(tail, text: &text, thinking: &thinking, finished: &finished)
        }
        XCTAssertEqual(text, "AB")
        XCTAssertEqual(thinking, "why")
        XCTAssertEqual(finished?.evalCount, 2)
    }
}