import CairnChatDomain
import Foundation
import XCTest
@testable import CairnProviderRemote

/// The proof P4 owes: the real `NWListener`, real bytes on a real socket, in **both** dialects.
///
/// The domain suite proves the translation with a recorder; nothing there has ever been a socket. This
/// file is the half that can only run where `Network` exists, so it runs on the macOS host lane.
/// Loopback only — `127.0.0.1` is the documented example address, the classifier calls it the local
/// link, and a loopback listener needs no network access and no ATS exception, which is what keeps the
/// job hermetic.
@MainActor
final class ShareLoopbackTests: XCTestCase {
    private let shareToken = ShareToken.generate()
    private let session = URLSession(configuration: .ephemeral)

    /// One mock engine behind the surface, so an answer is deterministic and nothing real runs.
    private func engines() -> [any InferenceProvider] {
        [MockStreamingProvider(id: "cairn-mock", thinkingCapable: false, tokenDelayNanoseconds: 0)]
    }

    /// Binds a surface, runs the checks against it, and closes the port whatever the checks did.
    ///
    /// `stop()` cannot be awaited inside `defer`, so both exit paths are written out: an assertion that
    /// fails must not leave a listener sitting on a port for the next test.
    private func withSurface(_ run: @MainActor (CairnShareServer) async throws -> Void) async throws {
        guard let server = try await ShareLoopbackTests.bind(engines: { self.engines() }, token: shareToken) else {
            throw XCTSkip("loopback listener unavailable on this runner")
        }
        var failure: (any Error)?
        do { try await run(server) } catch { failure = error }
        await server.stop()
        if let failure { throw failure }
    }

    /// A surface on a loopback port, or nil when this runner will not bind at all.
    private static func bind(
        engines enginesSource: @escaping @MainActor () -> [any InferenceProvider],
        token: String
    ) async throws -> CairnShareServer? {
        for attempt in 0..<4 {
            let port = 41_000 + Int(getpid() % 900) + attempt * 11
            let server = CairnShareServer(engines: enginesSource, addressSource: { "127.0.0.1" })
            if (await server.start(port: port, token: token, engineIDs: ["cairn-mock"])).isAllowed { return server }
        }
        return nil
    }

    /// One HTTP call, answered as a status and the whole body. The key rides in the header real
    /// clients use, so the auth path is proven against a real request rather than a hand-built struct.
    private func call(
        _ server: CairnShareServer,
        _ method: String,
        _ path: String,
        body: String? = nil,
        key: String?
    ) async throws -> (Int, String) {
        guard let url = URL(string: "http://127.0.0.1:\(server.status.port)\(path)") else {
            throw XCTSkip("no loopback url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await session.bytes(for: request)
        var text = ""
        for try await line in bytes.lines { text += line + "\n" }
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, text)
    }

    func testTheModelListIsKeyedAndNamesOnlyTheSharedEngine() async throws {
        try await withSurface { server in
            let anonymous = try await self.call(server, "GET", "/api/tags", key: nil)
            XCTAssertEqual(anonymous.0, 401, "a model list is a discovery beacon without the key")

            let keyed = try await self.call(server, "GET", "/api/tags", key: self.shareToken)
            XCTAssertEqual(keyed.0, 200)
            XCTAssertTrue(keyed.1.contains("cairn-mock"))

            let openAIList = try await self.call(server, "GET", "/v1/models", key: self.shareToken)
            XCTAssertEqual(openAIList.0, 200)
            XCTAssertTrue(openAIList.1.contains("cairn-mock"))

            let wrongKey = try await self.call(server, "GET", "/api/tags", key: "not-the-key-at-all-here")
            XCTAssertEqual(wrongKey.0, 401)
        }
    }

    func testOllamaChatStreamsNdjsonOverTheWireAndTerminates() async throws {
        try await withSurface { server in
            let body = #"{"model":"cairn-mock","messages":[{"role":"user","content":"hello from the laptop"}],"stream":true}"#
            let answer = try await self.call(server, "POST", "/api/chat", body: body, key: self.shareToken)

            XCTAssertEqual(answer.0, 200)
            XCTAssertTrue(answer.1.contains("Mock answer to:"), "the answer has to reach the wire")
            XCTAssertTrue(answer.1.contains("hello from the laptop"))
            XCTAssertTrue(answer.1.contains("\"done\":true"), "a stream must state its own end")
        }
    }

    func testOpenAIChatCompletionsAnswersInItsOwnShape() async throws {
        try await withSurface { server in
            let body = #"{"model":"cairn-mock","messages":[{"role":"user","content":"hello from the laptop"}],"stream":false}"#
            let answer = try await self.call(server, "POST", "/v1/chat/completions", body: body, key: self.shareToken)

            XCTAssertEqual(answer.0, 200)
            XCTAssertTrue(answer.1.contains("\"choices\""))
            XCTAssertTrue(answer.1.contains("Mock answer to:"))
        }
    }

    func testANameWithNoEngineBehindItIsRefusedRatherThanInvented() async throws {
        try await withSurface { server in
            let body = #"{"model":"some-model-not-shared","messages":[{"role":"user","content":"hi"}],"stream":false}"#
            let answer = try await self.call(server, "POST", "/api/chat", body: body, key: self.shareToken)
            XCTAssertEqual(answer.0, 503)
            XCTAssertTrue(answer.1.contains("no engine behind that name"))
        }
    }

    func testClosingTheSurfaceReallyClosesThePort() async throws {
        guard let server = try await ShareLoopbackTests.bind(engines: { self.engines() }, token: shareToken) else {
            throw XCTSkip("loopback listener unavailable on this runner")
        }
        let version = try await self.call(server, "GET", "/api/version", key: shareToken)
        XCTAssertEqual(version.0, 200)
        XCTAssertTrue(version.1.contains(ShareSettings.servedVersion), "the surface names Cairn, not Ollama")

        await server.stop()
        XCTAssertEqual(server.status.state, .off)

        do {
            _ = try await self.call(server, "GET", "/api/version", key: shareToken)
            XCTFail("a closed port must refuse rather than answer from memory")
        } catch {
            // Refused is the right answer; which URLError the runner reports is the runner's business.
        }
    }
}
