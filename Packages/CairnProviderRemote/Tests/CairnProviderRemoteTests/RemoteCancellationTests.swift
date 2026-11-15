import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// Stop has to actually stop: cancelling the turn must close the producer, and the failure
/// vocabulary must teach the fix without ever carrying a URL, a host, or a token.
final class RemoteCancellationTests: XCTestCase {

    private func stalledStream() -> (StubTransport, AsyncThrowingStream<StreamChunk, any Error>) {
        let transport = StubTransport(["/api/chat": .stalled(after: ollamaLine(content: "first"))])
        let provider = RemoteChatProvider(profile: Fixtures.ollama(), bearer: nil, transport: transport)
        return (transport, provider.stream(Fixtures.request()))
    }

    func testStoppingMidStreamClosesTheProducer() async throws {
        let (transport, stream) = stalledStream()
        let consumer = Task { () -> Int in
            var seen = 0
            for try await chunk in stream {
                if case .content = chunk { seen += 1 }
            }
            return seen
        }
        // Let the first token land, then press Stop.
        try? await Task.sleep(for: .milliseconds(150))
        consumer.cancel()

        // Returning at all is the assertion: a stream that cannot be closed would hang here.
        _ = await consumer.result
        let closed = await waitUntil(.seconds(2)) { transport.abandonCount > 0 }
        XCTAssertTrue(closed, "Stop must close the producer, or generation keeps running on the server")
    }

    func testCancellingBeforeTheFirstTokenStillClosesTheProducer() async throws {
        let (transport, stream) = stalledStream()
        let consumer = Task { () -> Bool in
            do {
                for try await _ in stream { }
            } catch {
                return true
            }
            return false
        }
        consumer.cancel()
        _ = await consumer.result
        let closed = await waitUntil(.seconds(2)) { transport.abandonCount > 0 }
        XCTAssertTrue(closed)
    }

    func testCancellationAndTransportFailuresMapToTeachingCases() {
        XCTAssertEqual(RemoteError.classify(CancellationError()), .cancelled)
        XCTAssertEqual(RemoteError.classify(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(RemoteError.classify(URLError(.timedOut)), .timedOut)
        XCTAssertEqual(RemoteError.classify(URLError(.cannotFindHost)), .hostNotFound)
        XCTAssertEqual(RemoteError.classify(URLError(.dnsLookupFailed)), .hostNotFound)
        XCTAssertEqual(RemoteError.classify(URLError(.cannotConnectToHost)), .connectionRefused)
        XCTAssertEqual(RemoteError.classify(URLError(.secureConnectionFailed)), .tlsFailure)
        XCTAssertEqual(
            RemoteError.classify(URLError(.appTransportSecurityRequiresSecureConnection)),
            .plainHTTPBlocked
        )
    }

    func testUserPresentableTextNeverCarriesAURLHostOrSecret() {
        let errors: [RemoteError] = [
            .invalidURL, .cancelled, .timedOut, .hostNotFound, .tlsFailure, .connectionRefused,
            .plainHTTPBlocked, .optInRequired, .unsupportedOperation, .malformedResponse,
            .httpStatus(502, serverMessage: nil), .serverMessage("bad request"),
            .transport("connection lost"),
        ]
        for error in errors {
            let text = error.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty, "every failure needs a message the UI can show")
            for forbidden in ["http://", "https://", "ts.net", "127.0.0.1", "Bearer", "sk-"] {
                XCTAssertFalse(
                    text.contains(forbidden),
                    "a failure string may reach a crash report, so it may not contain \(forbidden)"
                )
            }
        }
    }
}
