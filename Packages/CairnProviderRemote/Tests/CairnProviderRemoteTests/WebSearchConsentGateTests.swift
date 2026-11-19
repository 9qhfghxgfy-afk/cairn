import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// Consent, checked before the socket: the tool asks a person, and a "no" costs nothing at all.
///
/// Three separate conditions, which the old wording collapsed into one "not allowed":
///
/// - **Asked and allowed** — the search runs, and the app persists the grant so it is not asked again.
/// - **Asked and refused** — a typed refusal, zero requests, and the question is not asked again either.
/// - **Nobody to ask** — a preview, a test host, a build with no sheet. That is *not* consent, so the
///   search refuses and says the question is still open.
///
/// A row on the user's own network is in a fourth category: it is not a third party, the acknowledgement
/// they already gave covers it, and a sheet that asks nothing would only train them to tap through it.
@MainActor
final class WebSearchConsentGateTests: XCTestCase {

    private let page = """
        <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fparis">Rain</a>
        <div class="result__snippet">A wet city.</div>
        """

    private func requester(_ recorder: ConsentRecorder) -> WebSearchConsentRequester {
        { profile in await recorder.request(profile) }
    }

    func testAPublicProviderIsAskedOnceAndThenSearches() async throws {
        let recorder = ConsentRecorder(answer: true)
        let (search, transport) = searchTool(
            searchState(consent: .undecided), reply: .html(page), consent: requester(recorder)
        )
        let outcome = try await search.execute(searchCall("rain in Paris"), context: armedContext)

        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(recorder.askedProviderNames, ["DuckDuckGo"], "named by the row, not by the tool")
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testADeclineIsATypedRefusalWithZeroRequests() async {
        let recorder = ConsentRecorder(answer: false)
        let (search, transport) = searchTool(
            searchState(consent: .undecided), reply: .html(page), consent: requester(recorder)
        )
        do {
            _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
            XCTFail("a refusal is a typed failure, not an empty result")
        } catch let thrown as ToolFailure {
            XCTAssertEqual(thrown.error, .internetNotAllowed)
            XCTAssertTrue(
                (thrown.detail ?? "").contains("has not allowed"),
                "the model must read a person's decision, not a broken tool"
            )
        } catch {
            XCTFail("expected a typed failure, threw \(type(of: error))")
        }
        XCTAssertEqual(recorder.askedCount, 1, "asked once, as it should have been")
        XCTAssertEqual(transport.requestCount, 0, "refused before the socket")
        XCTAssertEqual(transport.byteLimits, [], "not even a request was built")
    }

    func testNobodyToAskRefusesWithoutInventingConsent() async {
        let (search, transport) = searchTool(searchState(consent: .undecided), reply: .html(page))
        do {
            _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
            XCTFail("a build with no sheet may not assume a yes")
        } catch let thrown as ToolFailure {
            XCTAssertEqual(thrown.error, .internetNotAllowed)
            XCTAssertTrue(
                (thrown.detail ?? "").contains("has to ask"),
                "an open question is named as one, so Settings is where the user goes"
            )
        } catch {
            XCTFail("expected a typed failure, threw \(type(of: error))")
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testAnInstanceOnTheUsersOwnNetworkIsNeverAskedAbout() async throws {
        // The recorder would say no. It is never consulted, because a query to the user's own box leaves
        // nothing they did not already opt into, and a sheet that asks nothing is noise that trains
        // people to tap through a warning.
        let recorder = ConsentRecorder(answer: false)
        let (search, transport) = searchTool(
            searchState(lanRow(), consent: .undecided), consent: requester(recorder)
        )
        let outcome = try await search.execute(searchCall("rain in Paris"), context: armedContext)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(recorder.askedCount, 0, "nothing to ask about a private row")
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testAStoredDenialIsHonouredWithoutAskingAgain() async {
        let recorder = ConsentRecorder(answer: true)
        let (search, transport) = searchTool(
            searchState(consent: .denied), reply: .html(page), consent: requester(recorder)
        )
        await expectSearchFailure(.internetNotAllowed) {
            try await search.execute(searchCall("rain in Paris"), context: armedContext)
        }
        XCTAssertEqual(recorder.askedCount, 0, "a stored no is an answer, not an annoyance to wear down")
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testAStoredGrantNeedsNoAskingEither() async throws {
        let recorder = ConsentRecorder(answer: false)
        let (search, transport) = searchTool(
            searchState(), reply: .html(page), consent: requester(recorder)
        )
        let outcome = try await search.execute(searchCall("rain in Paris"), context: armedContext)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(recorder.askedCount, 0)
        XCTAssertEqual(transport.requestCount, 1)
    }
}
