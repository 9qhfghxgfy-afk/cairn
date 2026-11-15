import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The OpenAI-compatible dialect plus the request-assembly rules: which endpoint, which
/// headers, and when a profile may not touch the network at all.
final class RemoteOpenAIStreamTests: XCTestCase {

    func testSSEStreamCarriesReasoningAndUsage() async throws {
        let body = sseLine(#"{"choices":[{"delta":{"reasoning_content":"pondering"}}]}"#)
            + sseLine(#"{"choices":[{"delta":{"content":"Hi"}}]}"#)
            + sseLine(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
            + sseLine(#"{"usage":{"prompt_tokens":7,"completion_tokens":3}}"#)
            + sseLine("[DONE]")
        let transport = StubTransport(["/v1/chat/completions": .body(body)])
        let provider = RemoteChatProvider(profile: Fixtures.openAI(), bearer: nil, transport: transport)

        let got = try await collect(provider.stream(Fixtures.request()))
        XCTAssertEqual(got.thinking, "pondering")
        XCTAssertEqual(got.content, "Hi")
        XCTAssertEqual(got.metrics?.tokensGenerated, 3)
        XCTAssertEqual(got.metrics?.promptTokens, 7)
        XCTAssertEqual(got.metrics?.finishReason, .stop)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
    }

    func testHTTPStatusCarriesTheServersOwnMessage() async throws {
        let transport = StubTransport([
            "/v1/chat/completions": .rejected(status: 401, errorJSON: #"{"error":{"message":"invalid api key"}}"#),
        ])
        let provider = RemoteChatProvider(profile: Fixtures.openAI(), bearer: nil, transport: transport)
        do {
            _ = try await collect(provider.stream(Fixtures.request()))
            XCTFail("a rejected request must throw")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .httpStatus(401, serverMessage: "invalid api key"))
        }
    }

    func testTokenComesFromTheCallerAndCredentialHeadersAreDropped() async throws {
        var profile = Fixtures.ollama(token: true)
        // Validation already rejects these; the request builder drops them as defence in depth.
        profile.customHeaders = ["Authorization": "Bearer pasted-into-settings", "X-Request-Tag": "cairn"]
        let transport = StubTransport([
            "/api/chat": .body(ollamaLine(content: "ok", done: true, reason: "stop", evalCount: 1)),
        ])
        let provider = RemoteChatProvider(profile: profile, bearer: "sk-from-keychain", transport: transport)

        _ = try await collect(provider.stream(Fixtures.request()))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-from-keychain")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-Tag"), "cairn")
    }

    func testCatalogDecodesForBothDialects() async throws {
        let ollamaTransport = StubTransport([
            "/api/tags": .body(#"{"models":[{"name":"qwen3:8b","details":{"parameter_size":"8B","quantization_level":"Q4_K_M","projector":"clip","supports_thinking":true}}]}"#),
        ])
        let ollama = RemoteChatProvider(profile: Fixtures.ollama(), bearer: nil, transport: ollamaTransport)
        let ollamaModels = try await ollama.models()
        XCTAssertEqual(ollamaModels.map(\.id), ["qwen3:8b"])
        XCTAssertEqual(ollamaModels.first?.quantization, "Q4_K_M")
        XCTAssertTrue(ollamaModels.first?.supportsVision ?? false)
        XCTAssertTrue(ollamaModels.first?.supportsThinking ?? false)

        let openAITransport = StubTransport(["/v1/models": .body(#"{"data":[{"id":"gpt-ish"},{"id":"other"}]}"#)])
        let openAI = RemoteChatProvider(profile: Fixtures.openAI(), bearer: nil, transport: openAITransport)
        let openAIModels = try await openAI.models()
        XCTAssertEqual(openAIModels.map(\.id), ["gpt-ish", "other"])
        // A listing without metadata invents nothing.
        XCTAssertFalse(openAIModels.first?.supportsThinking ?? true)
    }

    func testPublicInternetProfileStaysInertWithoutOptIn() async throws {
        let transport = StubTransport(["/v1/models": .body(#"{"data":[]}"#)])
        let withoutOptIn = RemoteChatProvider(
            profile: Fixtures.cloud(optIn: false), bearer: nil, transport: transport
        )
        do {
            _ = try await withoutOptIn.models()
            XCTFail("a non-opted-in public profile must not make a request")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .optInRequired)
        }

        let withOptIn = RemoteChatProvider(
            profile: Fixtures.cloud(optIn: true), bearer: nil, transport: transport
        )
        _ = try await withOptIn.models()
        XCTAssertEqual(transport.requests.count, 1, "only the opted-in profile reached the network")
    }
}
