import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The write side and the gates: cancelling a download, releasing a loaded model, and the
/// servers that must be told "not here" instead of being sent a request they cannot answer.
@MainActor
final class ModelLifecycleWriteTests: XCTestCase {
    private func makeLifecycle(_ replies: [String: StubTransport.Reply]) -> (RemoteModelLifecycleService, StubTransport) {
        let transport = StubTransport(replies)
        return (RemoteModelLifecycleService(transport: transport, secrets: WireFixtures.secrets()), transport)
    }

    private func lmStudio() -> ServerProfile { WireFixtures.studio }

    /// The point of the `abandon` handle: cancelling must close the connection, not merely stop
    /// reading, or a multi-gigabyte download keeps running behind a stopped UI.
    func testCancellingAPullAbandonsTheConnection() async throws {
        let (service, transport) = makeLifecycle([
            "/api/pull": .stalled(after: #"{"status":"pulling manifest"}"# + "\n"),
        ])
        // The stream is created inside the task and dropped when the task ends, which is what Stop
        // looks like from here: the consumer walks away while the server is still sending.
        let consumer = Task { @MainActor in
            let download = service.pull(model: "big", profile: Fixtures.ollama())
            for try await _ in download { return }
        }
        try await consumer.value

        for _ in 0..<50 where transport.abandonCount == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(transport.abandonCount, 0, "Stop must close the socket")
    }

    func testUnloadSendsKeepAliveZeroAndKeepsTheModelInstalled() async throws {
        let (service, transport) = makeLifecycle(["/api/generate": .body("{}")])
        try await service.unload(model: "qwen3:8b", profile: Fixtures.ollama())
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/generate")
        let sent = String(data: transport.requests.first?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sent.contains("keep_alive"), "release must use the documented keep_alive form")
        XCTAssertTrue(sent.contains("qwen3:8b"))
    }

    func testGenericOpenAIServerGetsCopyRatherThanLifecycle() async throws {
        let (service, transport) = makeLifecycle([:])
        let profile = Fixtures.openAI()
        XCTAssertFalse(service.supportsLifecycle(profile))
        XCTAssertTrue(service.guidance(profile).contains("Ollama"))
        XCTAssertTrue(service.guidance(profile).contains("On-Device"))
        do {
            _ = try await service.runningModels(profile)
            XCTFail("a gated call must not reach the network")
        } catch let issue as ModelLifecycleError {
            XCTAssertEqual(issue, .unsupported(.openAICompatible))
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    /// A public-internet profile is refused before the request is built, so no credential and no
    /// byte can leave without the opt-in.
    func testPublicInternetProfileIsRefusedBeforeAnyRequest() async throws {
        let away = ServerProfile(
            name: "Away", kind: .ollama, baseURLString: Fixtures.cloud, publicInternetOptIn: false
        )
        let (service, transport) = makeLifecycle(["/api/pull": .body("{}")])
        do {
            for try await _ in service.pull(model: "qwen3:8b", profile: away) {}
            XCTFail("the opt-in must be checked first")
        } catch let issue as ModelLifecycleError {
            XCTAssertEqual(issue, .optInRequired)
        }
        XCTAssertTrue(transport.requests.isEmpty, "refused means no socket was opened")
    }

    // MARK: - LM Studio, tolerant decoding (payload shapes pending a real server)

    func testLMStudioRunningModelsComeFromItsOwnList() async throws {
        let (service, transport) = makeLifecycle([
            "/api/v1/models": .body(#"{"data":[{"key":"qwen3-8b","running":true},{"key":"idle-one","running":false}]}"#),
        ])
        let loaded = try await service.runningModels(lmStudio())
        XCTAssertEqual(loaded.map(\.id), ["qwen3-8b"], "only a model the server says is running is resident")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/v1/models")
    }

    func testLMStudioUnloadTargetsItsNativeRouteAndReportsRefusal() async throws {
        let (service, transport) = makeLifecycle(["/api/v1/models/unload": .body(#"{"error":"busy"}"#)])
        do {
            try await service.unload(model: "qwen3-8b", profile: lmStudio())
            XCTFail("a refusal must not be reported as success")
        } catch let issue as ModelLifecycleError {
            XCTAssertEqual(issue, .serverMessage("busy"))
        }
        let sent = String(data: transport.requests.first?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sent.contains("qwen3-8b"))
    }
}
