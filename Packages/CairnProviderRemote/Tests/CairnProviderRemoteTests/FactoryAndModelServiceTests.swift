import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// Engine registration and model management. Both are gated on capability and consent, not
/// on the UI having hidden the button: a dialect without an endpoint is refused before a
/// request is built, and a profile without opt-in never becomes an engine.
@MainActor
final class FactoryAndModelServiceTests: XCTestCase {

    private func secrets() -> KeychainSecretStore {
        KeychainSecretStore(operation: FakeKeychainOperator())
    }

    func testDisabledAndNonOptedInProfilesProduceNoEngine() {
        var disabled = Fixtures.ollama()
        disabled.enabled = false
        let factory = RemoteProviderFactory(transport: StubTransport(), secrets: secrets())

        let engines = factory.providers(from: [disabled, Fixtures.cloud(optIn: false), Fixtures.ollama(), Fixtures.openAI()])

        XCTAssertEqual(engines.count, 2, "only usable profiles become engines")
        XCTAssertEqual(engines.first?.capabilities, .ollama)
        XCTAssertEqual(engines.last?.capabilities, .openAICompatible)
        XCTAssertTrue(engines.allSatisfy { $0.id.hasPrefix("remote:") })
    }

    func testPullIsRefusedForADialectWithoutThatEndpoint() async throws {
        let transport = StubTransport(["/api/pull": .body("{}")])
        let service = RemoteModelService(transport: transport, secrets: secrets())
        do {
            try await service.pull(model: "qwen3:8b", profile: Fixtures.openAI())
            XCTFail("an OpenAI-compatible server has no pull endpoint")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .unsupportedOperation)
        }
        XCTAssertTrue(transport.requests.isEmpty, "refusing must not issue a request that would 404")
    }

    func testLoadedModelsComeFromTheRunningModelsEndpoint() async throws {
        let transport = StubTransport(["/api/ps": .body(#"{"models":[{"name":"qwen3:8b"},{"name":"llama3.2"}]}"#)])
        let service = RemoteModelService(transport: transport, secrets: secrets())

        let loaded = try await service.loadedModels(Fixtures.ollama())
        XCTAssertEqual(loaded, ["qwen3:8b", "llama3.2"])
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/ps")
    }

    func testPullFailureInsideA200ProgressStreamStillFailsThePull() async throws {
        let transport = StubTransport([
            "/api/pull": .body("{\"status\":\"pulling manifest\"}\n{\"error\":\"pull failed: unauthorized\"}\n"),
        ])
        let service = RemoteModelService(transport: transport, secrets: secrets())
        do {
            try await service.pull(model: "qwen3:8b", profile: Fixtures.ollama())
            XCTFail("Ollama reports pull failures with HTTP 200, so the stream must be inspected")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .serverMessage("pull failed: unauthorized"))
        }
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("qwen3:8b") ?? false)
    }

    func testDeleteTargetsTheDeleteEndpoint() async throws {
        let transport = StubTransport(["/api/delete": .body("")])
        let service = RemoteModelService(transport: transport, secrets: secrets())

        try await service.delete(model: "qwen3:8b", profile: Fixtures.ollama())
        XCTAssertEqual(transport.requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/delete")
    }

    func testModelManagementOnAPrivateProfileNeverLeavesTheDeviceUnasked() async throws {
        let transport = StubTransport(["/api/tags": .body(#"{"models":[]}"#)])
        let service = RemoteModelService(transport: transport, secrets: secrets())

        _ = try await service.listModels(Fixtures.ollama())
        XCTAssertEqual(transport.requests.first?.url?.host, "127.0.0.1")
        do {
            _ = try await service.listModels(Fixtures.cloud(optIn: false))
            XCTFail("a public-internet profile without opt-in may not be queried")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .optInRequired)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }
}
