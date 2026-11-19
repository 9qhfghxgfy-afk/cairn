import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The two things decided before a socket opens: where the query is going, and whether anything is allowed
/// to ride along with it.
///
/// Both are asserted on the built request — or on the absence of one — because that is the only place they
/// can be checked. A test that reads a log line proves the code said something; a test that reads the
/// `URLRequest` proves what would have left the device.
///
/// The address rule is tested on a stored row even though the settings screen refuses to save such a row:
/// the screen's rule and the tool's rule are separate, and the tool's rule is what has to hold when a row
/// written under an older, looser rule is still sitting in the store.
@MainActor
final class WebSearchAddressAndKeyTests: XCTestCase {

    // MARK: the address, before any socket

    func testAPublicAddressOverPlainHttpIsRefusedBeforeTheSocket() async {
        let (search, transport) = searchTool(searchState(plaintextPublicRow()))
        do {
            _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
            XCTFail("a public host over http is refused, not badged")
        } catch let thrown as ToolFailure {
            XCTAssertEqual(thrown.error, .httpsRequired)
            XCTAssertTrue((thrown.detail ?? "").contains("was not sent"))
        } catch {
            // Named by type only: an error's own text can carry a host, and hosts do not belong in a log.
            XCTFail("expected a typed failure, threw \(type(of: error))")
        }
        XCTAssertEqual(transport.requestCount, 0, "refused before the socket")
    }

    func testAnUnusableAddressIsRefusedBeforeTheSocket() async {
        let broken = WebSearchProviderProfile(
            kind: .searxng, displayName: "Broken", baseURLString: "not an address"
        )
        let (search, transport) = searchTool(searchState(broken))
        await expectSearchFailure(.providerUnavailable) {
            try await search.execute(searchCall("rain in Paris"), context: armedContext)
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    // MARK: the cloud row, whose ability to search is someone's key

    func testACloudRowWithoutItsKeySendsNothingAndSaysWhy() async {
        let (search, transport) = searchTool(searchState(cloudRow()))
        do {
            _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
            XCTFail("a cloud row with no key cannot search")
        } catch let thrown as ToolFailure {
            XCTAssertEqual(thrown.error, .providerUnavailable)
            XCTAssertTrue(
                (thrown.detail ?? "").contains("no request was sent"),
                "a missing key is a configuration problem, not a search that found nothing"
            )
        } catch {
            XCTFail("expected a typed failure, threw \(type(of: error))")
        }
        XCTAssertEqual(transport.requestCount, 0, "no key, no request, no prompt mid-turn")
    }

    func testACloudRequestCarriesTheQueryAndTheCountAndNothingElse() async throws {
        let (search, transport) = searchTool(searchState(cloudRow(), credential: "cloud-key"))
        _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.host, "ollama.com")
        let fields = try RequestReader.bodyFields(sent)
        XCTAssertEqual(Set(fields.keys), ["query", "max_results"], "the smallest body that can ask")
        XCTAssertEqual(fields["query"] as? String, "rain in Paris")
        XCTAssertEqual(
            RequestReader.header(sent, "Authorization"), "Bearer cloud-key",
            "the key rides only to the host that issued it"
        )
        XCTAssertFalse(
            (sent.url?.absoluteString ?? "").contains("cloud-key"),
            "a credential never travels in an address"
        )
    }

    func testALanServersTokenIsNeverHandedToASearchRow() async throws {
        // The user's own row needs no credential, so a credential that happens to be in reach must not be
        // sprayed onto it — a token for one host arriving at another is the leak this wall prevents.
        let (search, transport) = searchTool(searchState(lanRow(), credential: "someone-elses-token"))
        _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertNil(RequestReader.header(sent, "Authorization"))
        XCTAssertNil(RequestReader.header(sent, "X-API-Key"))
    }
}
