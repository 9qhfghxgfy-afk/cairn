import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The half a stub cannot prove: the URLSession delegate, real status mapping, and Stop
/// against a live socket. Loopback only, so CI needs no network and no ATS exception.
final class LoopbackStreamTests: XCTestCase {

    private func requireLoopback(_ server: LocalStubServer?) throws -> LocalStubServer {
        guard let server else { throw XCTSkip("loopback listener unavailable on this runner") }
        return server
    }

    private func base(_ server: LocalStubServer) -> String {
        "http://127.0.0.1:\(server.port)"
    }

    private func provider(_ server: LocalStubServer) -> RemoteChatProvider {
        RemoteChatProvider(
            profile: Fixtures.ollama(base: base(server)),
            bearer: "sk-loopback",
            transport: URLSessionTransport()
        )
    }

    func testRealStackStreamsNDJSONIntoChunks() async throws {
        let server = try requireLoopback(LocalStubServer.start(routes: [
            LocalStubServer.Route(
                path: "/api/chat",
                pieces: [
                    ollamaLine(content: "hello "),
                    ollamaLine(content: "world", done: true, reason: "stop", evalCount: 2, promptEvalCount: 4),
                ],
                gapNanoseconds: 80_000_000
            ),
        ]))
        defer { server.stop() }

        let got = try await collect(provider(server).stream(Fixtures.request()))
        XCTAssertEqual(got.content, "hello world", "two writes must arrive as two callbacks, in order")
        XCTAssertEqual(got.metrics?.tokensGenerated, 2)
        XCTAssertEqual(got.metrics?.promptTokens, 4)
    }

    func testRealStackMapsNon2xxToATypedError() async throws {
        let server = try requireLoopback(LocalStubServer.start(routes: [
            LocalStubServer.Route(
                path: "/api/chat",
                status: 401,
                contentType: "application/json",
                pieces: [#"{"error":"unauthorized"}"#]
            ),
        ]))
        defer { server.stop() }

        do {
            _ = try await collect(provider(server).stream(Fixtures.request()))
            XCTFail("a 401 must fail the turn")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .httpStatus(401, serverMessage: "unauthorized"))
        }
    }

    func testStopAgainstASilentServerClosesTheSocket() async throws {
        // The server stays silent for 1.5 s, which is how a model that is still thinking looks.
        let server = try requireLoopback(LocalStubServer.start(routes: [
            LocalStubServer.Route(
                path: "/api/chat",
                pieces: [ollamaLine(content: "late")],
                openDelayNanoseconds: 1_500_000_000
            ),
        ]))
        defer { server.stop() }

        let stream = provider(server).stream(Fixtures.request())
        let consumer = Task { () -> Int in
            var seen = 0
            for try await _ in stream { seen += 1 }
            return seen
        }
        let started = ContinuousClock.now
        try? await Task.sleep(for: .milliseconds(200))
        consumer.cancel()
        _ = await consumer.result

        let waited = started.duration(to: ContinuousClock.now).components.seconds
        XCTAssertLessThan(waited, 2, "Stop must not wait for the server to answer")
        let gone = await waitUntil(.seconds(4)) {
            server.failedSendCount + server.peerClosedCount > 0
        }
        XCTAssertTrue(gone, "Stop has to close the socket, not just stop rendering")
    }
}
