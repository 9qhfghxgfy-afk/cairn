import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// Ollama streaming through the real pipeline with a stub transport: framing survives chunk
/// splits, and metrics only ever come from token counts the server actually reported.
final class RemoteOllamaStreamTests: XCTestCase {

    func testStreamSurvivesChunksSplitMidLine() async throws {
        let body = ollamaLine(thinking: "reasoning")
            + ollamaLine(content: "Hel")
            + ollamaLine(content: "lo")
            + ollamaLine(done: true, reason: "stop", evalCount: 2, promptEvalCount: 11)
        let bytes = Array(body.utf8)
        let cut = bytes.count / 2
        let transport = StubTransport([
            "/api/chat": .bytePieces([Array(bytes[..<cut]), Array(bytes[cut...])]),
        ])
        let provider = RemoteChatProvider(profile: Fixtures.ollama(), bearer: nil, transport: transport)

        let got = try await collect(provider.stream(Fixtures.request()))
        XCTAssertEqual(got.thinking, "reasoning")
        XCTAssertEqual(got.content, "Hello")
        XCTAssertEqual(got.metrics?.tokensGenerated, 2)
        XCTAssertEqual(got.metrics?.promptTokens, 11)
        XCTAssertEqual(got.metrics?.finishReason, .stop)
        XCTAssertNotNil(got.metrics?.timeToFirstTokenSeconds)
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/chat")
    }

    func testFinalLineWithoutTrailingNewlineStillCounts() async throws {
        let unterminated = ollamaLine(done: true, reason: "length", evalCount: 5).dropLast()
        let transport = StubTransport(["/api/chat": .body(ollamaLine(content: "hi") + unterminated)])
        let provider = RemoteChatProvider(profile: Fixtures.ollama(), bearer: nil, transport: transport)

        let got = try await collect(provider.stream(Fixtures.request()))
        XCTAssertEqual(got.content, "hi")
        XCTAssertEqual(got.metrics?.tokensGenerated, 5)
        XCTAssertEqual(got.metrics?.finishReason, .length)
    }

    func testSplitInsideAMultibyteCharacterStillDecodes() async throws {
        let bytes = Array(ollamaLine(content: "héllo").utf8)
        guard let accent = bytes.firstIndex(of: 0xC3) else {
            return XCTFail("fixture should carry a two-byte accent")
        }
        let next = bytes.index(after: accent)
        let transport = StubTransport([
            "/api/chat": .bytePieces([Array(bytes[...accent]), Array(bytes[next...])]),
        ])
        let provider = RemoteChatProvider(profile: Fixtures.ollama(), bearer: nil, transport: transport)

        let got = try await collect(provider.stream(Fixtures.request()))
        XCTAssertEqual(got.content, "héllo")
    }

    func testInBandServerErrorFailsTheTurnInsteadOfEndingItQuietly() async throws {
        let transport = StubTransport(["/api/chat": .body("{\"error\":\"model not found\"}\n")])
        let provider = RemoteChatProvider(profile: Fixtures.ollama(), bearer: nil, transport: transport)
        do {
            _ = try await collect(provider.stream(Fixtures.request()))
            XCTFail("an in-band error must surface as a failure")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .serverMessage("model not found"))
        }
    }

    func testThinkingIsNeverInventedWhenTheServerSendsNone() async throws {
        let transport = StubTransport([
            "/api/chat": .body(ollamaLine(content: "plain", done: true, reason: "stop", evalCount: 1)),
        ])
        let provider = RemoteChatProvider(profile: Fixtures.ollama(), bearer: nil, transport: transport)

        let got = try await collect(provider.stream(Fixtures.request(thinking: true)))
        XCTAssertTrue(got.thinking.isEmpty, "no thinking field on the wire means no reasoning panel")
    }

    func testStreamWithNoReportedTokensReportsNoMetrics() async throws {
        let transport = StubTransport(["/api/chat": .body(ollamaLine(content: "hi", done: true, reason: "stop"))])
        let provider = RemoteChatProvider(profile: Fixtures.ollama(), bearer: nil, transport: transport)

        let got = try await collect(provider.stream(Fixtures.request()))
        XCTAssertEqual(got.content, "hi")
        XCTAssertNil(got.metrics, "counts are measured, never estimated")
    }
}
