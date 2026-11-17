import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// LM Studio's kind at the wire level. What is claimed here is only what this machine can prove
/// without the app: which endpoint each surface is addressed at, how a request is encoded, how a
/// response is decoded, and that the lifecycle routes are declared but refused. That a real LM
/// Studio server behaves this way is a separate claim, still unverified — see the real-network
/// column in `docs/PARITY.md`.
@MainActor
final class LMStudioWireTests: XCTestCase {

    func testItChatsInTheOpenAIDialectAndListsFromItsOwn() {
        let wire = remoteWire(for: WireFixtures.studio)

        XCTAssertEqual(
            wire.chatPath, "/v1/chat/completions",
            "LM Studio publishes the OpenAI-compatible route on the same port, so chat uses it"
        )
        XCTAssertEqual(wire.modelsPath, "/api/v1/models", "and the catalog comes from its native REST surface")
        XCTAssertEqual(wire.chatAccept, "text/event-stream")
        XCTAssertEqual(wire.listAccept, "application/json")
    }

    /// M3b closed the gate that this test used to hold shut: LM Studio's native lifecycle routes
    /// are now really issued, by `RemoteModelLifecycleService`. What still has to hold is that the
    /// OLD boundary refuses the operations this kind does not have, and refuses without issuing a
    /// request that would only 404. The route PAYLOADS remain pending verification against a real
    /// server, which ROADMAP.md says out loud rather than resolving by flipping a flag.
    func testLifecycleRoutesAreDeclaredAndTheOldBoundaryStillRefusesWhatThisKindLacks() async throws {
        let transport = StubTransport(["/api/v1/models/load": .body("{}"), "/api/v1/models": .body("{}")])
        let service = RemoteModelService(transport: transport, secrets: WireFixtures.secrets())

        XCTAssertTrue(ServerProfileKind.lmStudio.backend.endpoints.lifecycleWired, "wired in M3b")
        XCTAssertEqual(ServerProfileKind.lmStudio.backend.endpoints.load, "/api/v1/models/load")
        XCTAssertEqual(ServerProfileKind.lmStudio.backend.endpoints.unload, "/api/v1/models/unload")

        do {
            try await service.pull(model: "qwen3-32b", profile: WireFixtures.studio)
            XCTFail("LM Studio has no pull endpoint on this kind")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .unsupportedOperation)
        }
        do {
            _ = try await service.loadedModels(WireFixtures.studio)
            XCTFail("LM Studio has no loaded-models endpoint on this kind")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .unsupportedOperation)
        }
        XCTAssertTrue(transport.requests.isEmpty, "refusing must not issue a request that would 404")
    }

    func testItSendsTheOpenAIBodyWithUsageAskedFor() throws {
        let body = try remoteWire(for: WireFixtures.studio)
            .chatBody(Fixtures.request(model: "qwen3-32b", thinking: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "qwen3-32b")
        XCTAssertEqual(json["stream"] as? Bool, true)
        let options = try XCTUnwrap(
            json["stream_options"] as? [String: Any],
            "usage is the only source of measured metrics, and it is off unless asked for"
        )
        XCTAssertEqual(options["include_usage"] as? Bool, true)
    }

    func testItListsFromItsOwnSurfaceAndReadsOnlyFieldsTheServerSent() async throws {
        let payload = #"{"data":[{"key":"qwen3-32b","name":"Qwen3 32B","vision":true},{"id":"gemma-3n","running":true}]}"#
        let transport = StubTransport(["/api/v1/models": .body(payload)])
        let service = RemoteModelService(transport: transport, secrets: WireFixtures.secrets())

        let models = try await service.listModels(WireFixtures.studio)

        XCTAssertEqual(models.map(\.id), ["qwen3-32b", "gemma-3n"], "the key the native list uses wins over an id")
        XCTAssertTrue(models[0].supportsVision)
        XCTAssertFalse(models[1].supportsVision, "an absent vision field stays false rather than being assumed")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/models")
        XCTAssertEqual(request.url?.port, 1234)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testAModelListThatIsNotAModelListIsATypedFailure() async throws {
        let transport = StubTransport(["/api/v1/models": .body(#"{"error":"no such route"}"#)])
        let service = RemoteModelService(transport: transport, secrets: WireFixtures.secrets())

        do {
            _ = try await service.listModels(WireFixtures.studio)
            XCTFail("inventing a model name would put one on screen that the server does not have")
        } catch let error as LMStudioCodec.DecodeError {
            XCTAssertEqual(error, .malformedPayload)
        }
    }

    func testItDecodesItsChatStreamAsOpenAISSE() throws {
        let wire = remoteWire(for: WireFixtures.studio)
        let content = try wire.decodeLine(Data(sseLine(#"{"choices":[{"delta":{"content":"Hi"}}]}"#).utf8))
        let usage = try wire.decodeLine(Data(sseLine(#"{"usage":{"prompt_tokens":7,"completion_tokens":3}}"#).utf8))
        // The parser hands over complete lines with no terminators, so `[DONE]` is matched exactly.
        let done = try wire.decodeLine(Data("data: [DONE]".utf8))

        XCTAssertEqual(content, [.content("Hi")])
        XCTAssertTrue(usage.contains(.usage(promptTokens: 7, completionTokens: 3)))
        XCTAssertEqual(done, [.streamDone])
    }

    /// A reasoning panel appears because the server sent a `reasoning_content` field, and it appears
    /// for no other reason — the same decoder that must not invent one stays honest here.
    func testReasoningComesOnlyFromAFieldTheServerActuallySent() throws {
        let wire = remoteWire(for: WireFixtures.studio)
        let thought = try wire.decodeLine(
            Data(sseLine(#"{"choices":[{"delta":{"reasoning_content":"weighing two options"}}]}"#).utf8)
        )
        let plain = try wire.decodeLine(Data(sseLine(#"{"choices":[{"delta":{"content":"answer"}}]}"#).utf8))

        XCTAssertEqual(thought, [.thinking("weighing two options")])
        XCTAssertEqual(plain, [.content("answer")], "no reasoning field means no reasoning chunk")
    }
}

