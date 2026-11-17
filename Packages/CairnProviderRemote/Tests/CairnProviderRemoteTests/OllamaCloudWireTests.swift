import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// Ollama Cloud's kind at the wire level, and the important half of P1: until the user turns it on
/// and allows traffic to leave the device, this profile is inert — not a refused packet, no packet.
/// That the real ollama.com behaves as its documentation says is not claimed here and is not
/// verified by these tests; the capability flags are what keep that honest in the meantime.
@MainActor
final class OllamaCloudWireTests: XCTestCase {

    func testItAddressesOllamasOwnEndpointsAndDialect() {
        let wire = remoteWire(for: WireFixtures.cloud)

        XCTAssertEqual(wire.chatPath, "/api/chat")
        XCTAssertEqual(wire.modelsPath, "/api/tags")
        XCTAssertEqual(wire.chatAccept, "application/x-ndjson", "Ollama streams NDJSON, not SSE")
    }

    func testItClaimsOnlyWhatItsOwnDocumentationSupports() {
        let capabilities = remoteWire(for: WireFixtures.cloud).capabilities

        XCTAssertFalse(capabilities.modelPull, "Ollama's create and delete routes need a local server")
        XCTAssertFalse(capabilities.modelDelete)
        XCTAssertFalse(capabilities.thinking, "no reasoning panel for a backend not seen to emit one")
    }

    func testOperationsItDoesNotSupportAreRefusedBeforeAnyRequest() async throws {
        let transport = StubTransport(["/api/pull": .body("{}"), "/api/chat": .body("{}")])
        let service = RemoteModelService(transport: transport, secrets: WireFixtures.secrets())

        do {
            try await service.pull(model: "qwen3:8b", profile: WireFixtures.optedInCloud)
            XCTFail("the cloud kind has no pull endpoint")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .unsupportedOperation)
        }
        do {
            _ = try await service.loadedModels(WireFixtures.optedInCloud)
            XCTFail("the cloud kind has no loaded-models endpoint")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .unsupportedOperation)
        }
        XCTAssertTrue(transport.requests.isEmpty, "refusing must not issue a request that would 404")
    }

    /// `think` is left out regardless of the request's toggle: the rule is never to ask a backend
    /// for reasoning it has not been observed producing.
    func testItIsNeverAskedForReasoningItHasNotBeenSeenToEmit() throws {
        let body = try remoteWire(for: WireFixtures.cloud)
            .chatBody(Fixtures.request(model: "qwen3:8b", thinking: true))
        let text = String(data: body, encoding: .utf8) ?? ""

        XCTAssertFalse(text.contains("\"think\""), "the toggle is ignored for this kind on purpose")
        XCTAssertTrue(text.contains("\"stream\":true"))
        XCTAssertTrue(text.contains("qwen3:8b"))
    }

    func testItSpeaksOllamasOwnNDJSONDialect() throws {
        let line = Data(ollamaLine(content: "hello", done: true, reason: "stop", evalCount: 7).utf8)

        let events = try remoteWire(for: WireFixtures.cloud).decodeLine(line)

        XCTAssertTrue(events.contains(.content("hello")))
        XCTAssertTrue(events.contains(.usage(promptTokens: nil, completionTokens: 7)))
        XCTAssertTrue(events.contains(.finished(.stop)))
    }

    // MARK: - Inert until the user says otherwise

    /// Inert means no packet, not a packet that gets refused: a profile the user has not opted in
    /// must never reach the network, and a token must never travel to a host they did not enable.
    func testItIsInertWithoutTheOptInAndSendsNothing() async throws {
        let transport = StubTransport(["/api/tags": .body(#"{"models":[]}"#), "/api/chat": .body("{}")])
        let provider = RemoteChatProvider(
            profile: WireFixtures.cloud, bearer: "sk-should-not-travel", transport: transport
        )

        do {
            _ = try await provider.models()
            XCTFail("a public-internet profile may not be queried without the outbound opt-in")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .optInRequired)
        }

        do {
            for try await _ in provider.stream(Fixtures.request()) {}
            XCTFail("a stream must not open against a profile the user has not opted in to")
        } catch let error as RemoteError {
            XCTAssertEqual(error, .optInRequired)
        }

        XCTAssertTrue(transport.requests.isEmpty, "inert means nothing leaves the device")
    }

    func testWithTheOptInAndAKeychainTokenItSendsOneRequestWithThatToken() async throws {
        let profile = WireFixtures.optedInCloud
        let store = WireFixtures.secrets()
        try store.setSecret("sk-cloud", for: profile.id)
        let transport = StubTransport(["/api/tags": .body(#"{"models":[{"name":"qwen3:8b"}]}"#)])

        let provider = RemoteChatProvider(
            profile: profile, bearer: store.secret(for: profile.id), transport: transport
        )
        let models = try await provider.models()

        XCTAssertEqual(models.map(\.id), ["qwen3:8b"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.host, ServerBackend.cloudHost, "the kind is pinned to the host it names")
        XCTAssertEqual(request.url?.scheme, "https", "a public-internet profile is https, always")
        XCTAssertEqual(request.url?.path, "/api/tags")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-cloud")
    }

    /// The label has to match where the traffic actually goes: a profile called Ollama Cloud that
    /// points at someone's own machine would be handed cloud rules it does not have.
    func testItIsRefusedForAnyHostOtherThanTheOneItNames() {
        XCTAssertThrowsError(
            try ServerProfile.validate(
                name: "Cloud", kind: .ollamaCloud, urlString: "https://someone-else.example", headers: [:]
            )
        )
        XCTAssertNoThrow(
            try ServerProfile.validate(name: "Cloud", kind: .ollamaCloud, urlString: "https://ollama.com", headers: [:])
        )
    }
}

