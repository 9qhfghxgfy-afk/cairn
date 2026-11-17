import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The Model Manager's server half: `/api/ps`, `/api/show` and a streaming `/api/pull`. Stub
/// transport only — no sockets, so this runs on a runner with no network at all.
@MainActor
final class ModelLifecycleReadTests: XCTestCase {
    func makeLifecycle(_ replies: [String: StubTransport.Reply]) -> (RemoteModelLifecycleService, StubTransport) {
        let transport = StubTransport(replies)
        return (RemoteModelLifecycleService(transport: transport, secrets: WireFixtures.secrets()), transport)
    }

    func testRunningModelsReadsApiPsIncludingVramAndExpiry() async throws {
        let json = """
        {"models":[{"name":"qwen3:8b","model":"qwen3:8b","size":5300000000,"size_vram":4100000000,\
        "expires_at":"2026-11-17T10:00:00.500Z","context_length":4096}]}
        """
        let (service, transport) = makeLifecycle(["/api/ps": .body(json)])

        let loaded = try await service.runningModels(Fixtures.ollama())
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "qwen3:8b")
        XCTAssertEqual(loaded.first?.memoryBytes, 5_300_000_000)
        XCTAssertEqual(loaded.first?.vramBytes, 4_100_000_000)
        XCTAssertEqual(loaded.first?.contextLength, 4096)
        XCTAssertNotNil(loaded.first?.expiresAt, "a fractional-seconds stamp must parse")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/ps")
    }

    func testDetailReportsOnlyPublishedFieldsAndNoInferredBadges() async throws {
        let published = """
        {"details":{"parameter_size":"8B","quantization_level":"Q4_K_M"},\
        "context_length":32768,"capabilities":["vision","tools"]}
        """
        let (service, _) = makeLifecycle(["/api/show": .body(published)])
        let detail = try await service.detail(model: "qwen3:8b", profile: Fixtures.ollama())
        XCTAssertEqual(detail.parameterSize, "8B")
        XCTAssertEqual(detail.quantization, "Q4_K_M")
        XCTAssertEqual(detail.contextLength, 32768)
        XCTAssertEqual(detail.capabilityLabels, ["Vision", "Tools"])

        // A server that states nothing earns no badges: a guessed badge is a claim the user acts on.
        let (quiet, _) = makeLifecycle(["/api/show": .body(#"{"details":{}}"#)])
        let bare = try await quiet.detail(model: "x", profile: Fixtures.ollama())
        XCTAssertTrue(bare.capabilityLabels.isEmpty)
        XCTAssertNil(bare.parameterSize)
    }

    func testPullStreamsProgressWithRealFractions() async throws {
        let lines = """
        {"status":"pulling manifest"}
        {"status":"pulling abc123","completed":25,"total":100}
        {"status":"pulling abc123","completed":100,"total":100}
        {"status":"success"}
        """
        let (service, transport) = makeLifecycle(["/api/pull": .body(lines)])
        var seen: [ModelPullProgress] = []
        for try await progress in service.pull(model: "qwen3:8b", profile: Fixtures.ollama()) {
            seen.append(progress)
        }
        XCTAssertEqual(seen.count, 4)
        XCTAssertEqual(seen[1].fraction ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertNil(seen[0].fraction, "no total named yet, so no denominator may be invented")
        XCTAssertEqual(seen.last?.statusText, "success")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/pull")
    }

    func testPullSurfacesAnInBandErrorDespiteHTTP200() async throws {
        let (service, _) = makeLifecycle([
            "/api/pull": .body(#"{"status":"pulling manifest"}"# + "\n" + #"{"error":"not found"}"# + "\n"),
        ])
        do {
            for try await _ in service.pull(model: "missing", profile: Fixtures.ollama()) {}
            XCTFail("an in-band failure must not look like progress")
        } catch let issue as ModelLifecycleError {
            guard case .serverMessage(let text) = issue else {
                return XCTFail("expected serverMessage, got \(issue)")
            }
            XCTAssertEqual(text, "not found")
        }
    }
}
