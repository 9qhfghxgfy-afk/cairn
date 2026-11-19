import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// What the Settings screen's "Test Connection" button is allowed to say.
///
/// Three promises, and all three are about the sentence the user reads:
///
/// - The tester asks one fixed, boring query. A tester that searched the last message would be a privacy
///   hole dressed as a button, and it would make the result count meaningless besides.
/// - A row that fails here fails with the same case the tool reports mid-turn. Two names for one condition
///   is how a settings screen ends up disagreeing with a tool card, and then the user has to work out
///   which one is lying.
/// - The hints are given only where they are true. Telling a DuckDuckGo user to edit their instance's
///   settings.yml is worse than telling them nothing.
final class WebSearchConnectionTesterTests: XCTestCase {

    private let threeResults = #"{"results":[{"title":"One","url":"https://example.com/one"},{"title":"Two","url":"https://example.com/two"},{"title":"Three","url":"https://example.com/three"}]}"#

    private func tester(
        reply: WebHTTPResponse,
        throws error: (any Error)? = nil
    ) -> (WebSearchConnectionTester, RecordingWebTransport) {
        let transport = RecordingWebTransport(reply: reply, throws: error)
        return (WebSearchConnectionTester(transport: transport), transport)
    }

    func testTheTestQueryIsFixedAndCarriesNothingFromTheConversation() async throws {
        let (tester, transport) = tester(reply: .json(threeResults))
        _ = await tester.run(profile: lanRow(name: "Box"), credential: nil)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(RequestReader.queryItems(sent)["q"], WebSearchConnectionTester.testQuery)
        XCTAssertEqual(transport.requestCount, 1, "one row, one request")
        XCTAssertNil(RequestReader.header(sent, "Authorization"))
        XCTAssertNil(sent.httpBody, "a GET with no body is a request that cannot hide a transcript")
    }

    func testAReachableInstanceIsReportedWithWhatItActuallyReturned() async {
        let (tester, _) = tester(reply: .json(threeResults))
        let status = await tester.run(profile: lanRow(), credential: nil, resultCount: 3)
        guard case .ok(let count, let milliseconds) = status else {
            return XCTFail("a box that answered three results tested as \(status)")
        }
        XCTAssertEqual(count, 3, "the count is what came back, not what was asked for")
        XCTAssertGreaterThanOrEqual(milliseconds, 0)
        XCTAssertTrue(
            status.detail(providerKind: .searxng).contains("Reachable"),
            "the line under the row says the row works"
        )
    }
    func testAnUnreachableRowIsNamedUnreachableRatherThanEmpty() async {
        let (tester, _) = tester(reply: .json("{}"), throws: URLError(.cannotConnectToHost))
        let status = await tester.run(profile: lanRow(), credential: nil)
        XCTAssertEqual(status, .failure(.unreachable))
        XCTAssertEqual(
            status.detail(providerKind: .searxng),
            "Cairn could not reach the search provider.",
            "the card says the box is unreachable, not that the web is empty"
        )
    }

    func testAnEmptyAnswerIsReachableAndEmptyAndSaysBoth() async {
        let (tester, _) = tester(reply: .json(#"{"results":[]}"#))
        let status = await tester.run(profile: lanRow(), credential: nil)
        XCTAssertEqual(status, .empty)
        XCTAssertTrue(
            status.detail(providerKind: .searxng).contains("returned nothing"),
            "the row works; the query found nothing — two different things a user can act on"
        )
    }

    func testARefusedSearXNGRowIsToldWhereToLook() async {
        // The common first-run failure of a self-hosted instance: JSON output is switched off, so the box
        // answers a human page and refuses the machine one.
        let (tester, _) = tester(reply: .html("<html>nope</html>", status: 403))
        let status = await tester.run(profile: lanRow(), credential: nil)
        XCTAssertEqual(status, .failure(.blocked))
        XCTAssertTrue(
            status.detail(providerKind: .searxng).contains("settings.yml"),
            "a hint that names the file the operator actually has to edit"
        )
    }

    func testAnUnreadableAnswerNamesJSONOnlyForAnInstanceThatHasJSON() async {
        let (tester, _) = tester(reply: .html("<html>a page, not a search</html>"))
        let instance = await tester.run(profile: lanRow(), credential: nil)
        XCTAssertEqual(instance, .failure(.unrecognizedResponse))
        XCTAssertTrue(
            instance.detail(providerKind: .searxng).contains("format=json"),
            "true of a SearXNG box, and the most common reason it happens"
        )

        let hosted = await tester.run(profile: .builtIn, credential: nil)
        XCTAssertEqual(hosted, .failure(.unrecognizedResponse))
        XCTAssertFalse(
            hosted.detail(providerKind: .duckDuckGo).contains("settings.yml"),
            "DuckDuckGo has no settings for the user to edit, so the hint would send them nowhere"
        )
    }

    func testACloudRowIsTestedWithItsOwnKeyAndWithNone() async throws {
        let (tester, transport) = tester(reply: .json(threeResults))
        let keyless = await tester.run(profile: cloudRow(), credential: nil)
        XCTAssertEqual(keyless, .failure(.providerUnavailable))
        XCTAssertEqual(transport.requestCount, 0, "no key, no request, no charge the user did not agree to")

        let armed = await tester.run(profile: cloudRow(), credential: "cloud-key")
        guard case .ok = armed else { return XCTFail("a row with its key must test reachable: \(armed)") }
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(RequestReader.header(sent, "Authorization"), "Bearer cloud-key")
        XCTAssertEqual(sent.url?.host, "ollama.com", "the tester only ever asks the row it was handed")
    }

    func testAPublicAddressOverPlainHttpIsRefusedBeforeTheSocket() async {
        let (tester, transport) = tester(reply: .json(threeResults))
        let status = await tester.run(profile: plaintextPublicRow(), credential: nil)
        XCTAssertEqual(status, .failure(.httpsRequired))
        XCTAssertEqual(transport.requestCount, 0, "refused before one word could leave unencrypted")
    }

    func testATimeoutDuringTheTestIsATimeoutAndNotAnEmptyWeb() async {
        let (tester, _) = tester(reply: .json("{}"), throws: URLError(.timedOut))
        let status = await tester.run(profile: lanRow(), credential: nil)
        XCTAssertEqual(status, .failure(.timedOut))
        XCTAssertTrue(
            status.detail(providerKind: .searxng).contains("too long"),
            "\"it took too long\" and \"it found nothing\" send the user to different fixes"
        )
    }
}
