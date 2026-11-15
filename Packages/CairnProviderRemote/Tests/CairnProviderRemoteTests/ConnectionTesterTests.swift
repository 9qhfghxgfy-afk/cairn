import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// A transport that fails on demand, so the hint-carrying outcomes can be reached without a
/// real dead hostname. The stored value is a code, not an error value: `any Error` is not
/// `Sendable`, and a transport has to be.
private struct AlwaysFailingTransport: RemoteTransport {
    var code: URLError.Code

    func open(_ request: URLRequest) -> RemoteByteStream {
        let failure = URLError(code)
        return RemoteByteStream(
            bytes: AsyncThrowingStream(Data.self, bufferingPolicy: .unbounded) {
                $0.finish(throwing: failure)
            },
            abandon: {}
        )
    }
}

/// "Test connection" in the profile editor: latency and counts come from real round trips,
/// every failure lands on the outcome that carries the teaching hint, and a profile that may
/// not talk never issues a request at all.
@MainActor
final class ConnectionTesterTests: XCTestCase {

    private func emptySecrets() -> KeychainSecretStore {
        KeychainSecretStore(operation: FakeKeychainOperator())
    }

    private func tester(_ transport: any RemoteTransport) -> RemoteConnectionTester {
        RemoteConnectionTester(transport: transport, secrets: emptySecrets())
    }

    func testConnectedReportsVersionCountAndLatency() async {
        let profile = Fixtures.ollama(token: true)
        let secrets = emptySecrets()
        try? secrets.setSecret("sk-test", for: profile.id)
        let transport = StubTransport([
            "/api/tags": .body(#"{"models":[{"name":"qwen3:8b"},{"name":"llama3.2"}]}"#),
            "/api/version": .body(#"{"version":"0.12.3"}"#),
        ])

        let outcome = await RemoteConnectionTester(transport: transport, secrets: secrets).test(profile)
        guard case .connected(let version, let count, let latency) = outcome else {
            return XCTFail("expected a connected result, got \(outcome)")
        }
        XCTAssertEqual(version, "0.12.3")
        XCTAssertEqual(count, 2)
        XCTAssertGreaterThan(latency, 0, "latency is measured, so it is never reported as zero")
        // The token reaches the wire as a bearer, from the Keychain, not from the record.
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testRejectedTokenBecomesTheUnauthorizedHint() async {
        let transport = StubTransport(["/api/tags": .rejected(status: 401)])
        let outcome = await tester(transport).test(Fixtures.ollama(token: true))
        XCTAssertEqual(outcome, .unauthorized)
        XCTAssertFalse(outcome.isSuccess)
        XCTAssertTrue(outcome.userMessage.contains("401"))
    }

    func testUnreachableHostBecomesTheTailscaleHint() async {
        let outcome = await tester(AlwaysFailingTransport(code: .cannotFindHost))
            .test(Fixtures.ollama(base: Fixtures.tailnet))
        XCTAssertEqual(outcome, .hostNotFound)
        XCTAssertTrue(outcome.userMessage.contains("MagicDNS"), "the hint must teach the fix")
    }

    func testPlaintextOffLoopbackIsRefusedWithoutAnyRequest() async {
        let transport = StubTransport(["/api/tags": .body(#"{"models":[]}"#)])
        let lanBox = ServerProfile(name: "Wired box", kind: .ollama, baseURLString: "http://10.0.0.5:11434")

        let outcome = await tester(transport).test(lanBox)
        XCTAssertEqual(outcome, .rejectedPlainHTTP)
        XCTAssertTrue(transport.requests.isEmpty, "refusing must happen before a request leaves")
    }

    func testPublicProfileWithoutOptInIsRefusedWithoutAnyRequest() async {
        let transport = StubTransport(["/v1/models": .body(#"{"data":[]}"#)])
        let outcome = await tester(transport).test(Fixtures.cloud(optIn: false))
        XCTAssertEqual(outcome, .optInRequired)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testLoopbackPlaintextIsAllowedForDevServers() async {
        let transport = StubTransport(["/api/tags": .body(#"{"models":[]}"#), "/api/version": .body("{}")])
        let outcome = await tester(transport).test(Fixtures.ollama())
        XCTAssertTrue(outcome.isSuccess, "loopback http is the dev / CI path: \(outcome)")
    }
}
