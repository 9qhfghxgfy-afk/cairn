import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The courtesy in front of a provider, and the one number that decides how much of the answer the model
/// gets.
///
/// Both are about the same thing seen from two sides: a tool loop can fire several searches inside one
/// turn, and each of them costs somebody — a shared public endpoint, or the user's own small box, which is
/// often the same machine as the model server. The cache answers an identical question from memory; the
/// gap paces the ones that genuinely have to go out; and the count is what keeps a ten-result answer from
/// eating the context budget of a small model.
final class WebSearchCourtesyAndCountTests: XCTestCase {

    /// A throttle with no pacing, so a test about the cache is not a test about sleeping.
    private func noGap() -> WebSearchThrottle {
        WebSearchThrottle(courtesy: WebSearchCourtesy(minimumGap: 0))
    }

    // MARK: memory-only de-duplication

    func testAnIdenticalSearchIsAnsweredFromMemoryWithoutASecondRequest() async throws {
        let pace = noGap()
        let state = searchState(lanRow())
        let (first, transport) = searchTool(state, throttle: pace)
        _ = try await first.execute(searchCall("rain in Paris"), context: armedContext)

        let (second, _) = searchTool(state, throttle: pace)
        let outcome = try await second.execute(searchCall("rain in Paris"), context: armedContext)

        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(transport.requestCount, 1, "one question, one request")
        XCTAssertTrue(
            outcome.modelText.contains("not a new request"),
            "a list a minute old is labelled as remembered, never as freshly asked"
        )
    }

    func testARepeatedQueryInDifferentCaseIsTheSameQuery() async throws {
        let pace = noGap()
        let state = searchState(lanRow())
        let (first, transport) = searchTool(state, throttle: pace)
        _ = try await first.execute(searchCall("Rain  in Paris"), context: armedContext)
        let (second, _) = searchTool(state, throttle: pace)
        _ = try await second.execute(searchCall("rain in paris"), context: armedContext)
        XCTAssertEqual(transport.requestCount, 1, "case and spacing are noise; the query is the query")
    }

    func testTwoProvidersDoNotShareOneCachedAnswer() async throws {
        // The mistake this prevents is the one worth being careful about: serving one provider's results as
        // another provider's, after the user has just switched.
        let pace = noGap()
        let box = searchState(lanRow(name: "Box"))
        let other = searchState(lanRow(name: "Other"))
        let (first, transport) = searchTool(box, throttle: pace)
        _ = try await first.execute(searchCall("rain in Paris"), context: armedContext)
        let (second, _) = searchTool(other, throttle: pace)
        _ = try await second.execute(searchCall("rain in Paris"), context: armedContext)
        XCTAssertEqual(transport.requestCount, 2, "a different row asks again")
    }

    func testDifferentParametersAreNotTheSameQuestion() async throws {
        // One row, two counts. Using two rows would pass for the wrong reason — the provider id is already
        // part of the key, and the point here is that the count is part of it too.
        let pace = noGap()
        let row = lanRow()
        let plain = searchState(row)
        let bounded = searchState(row, resultCount: 3)
        let (first, transport) = searchTool(plain, throttle: pace)
        _ = try await first.execute(searchCall("rain in Paris"), context: armedContext)
        let (second, _) = searchTool(bounded, throttle: pace)
        _ = try await second.execute(searchCall("rain in Paris"), context: armedContext)
        XCTAssertEqual(transport.requestCount, 2, "a different count is a different answer")
    }

    // MARK: pacing, which is what the gap is for

    func testASecondQueryWaitsOutTheGapRatherThanFiringAlongsideTheFirst() async throws {
        // A tool loop can issue three searches inside one turn. They may be three requests, but they must
        // not be three requests in the same 200 milliseconds — that is what gets a shared endpoint, or
        // somebody's small box, to refuse everyone.
        let pace = WebSearchThrottle(courtesy: WebSearchCourtesy(minimumGap: 0.4))
        let state = searchState(lanRow())
        let (first, transport) = searchTool(state, throttle: pace)
        _ = try await first.execute(searchCall("rain in Paris"), context: armedContext)

        let started = Date()
        let (second, _) = searchTool(state, throttle: pace)
        _ = try await second.execute(searchCall("snow in Oslo"), context: armedContext)
        let waited = Date().timeIntervalSince(started)

        XCTAssertEqual(transport.requestCount, 2, "both searches really went out")
        XCTAssertGreaterThanOrEqual(waited, 0.3, "the second waited out most of the gap")
    }

    func testATurnThatIsCancelledDoesNotGoOutLate() async {
        // The one case where waiting politely would mean doing the thing the user just stopped.
        let pace = WebSearchThrottle(courtesy: WebSearchCourtesy(minimumGap: 0.6))
        await pace.beginRequest()
        let waiting = Task { await pace.beginRequest() }
        try? await Task.sleep(nanoseconds: 80_000_000)
        waiting.cancel()
        let released = await waiting.value
        XCTAssertFalse(released, "the gap ended, and the request stayed unmade")
    }

    // MARK: the app-wide count

    func testTheAppWideCountBoundsWhatTheModelSees() async throws {
        let four = #"{"results":[{"title":"One","url":"https://example.com/one"},{"title":"Two","url":"https://example.com/two"},{"title":"Three","url":"https://example.com/three"},{"title":"Four","url":"https://example.com/four"}]}"#
        let (search, _) = searchTool(searchState(lanRow(), resultCount: 3), reply: .json(four))
        let outcome = try await search.execute(searchCall("rain in Paris"), context: armedContext)
        for url in ["one", "two", "three"] {
            XCTAssertTrue(outcome.modelText.contains("example.com/\(url)"), "\(url) is inside the count")
        }
        XCTAssertFalse(
            outcome.modelText.contains("example.com/four"),
            "the count is a bound on the prompt budget, not a suggestion"
        )
    }

    func testTheCountIsClampedIntoTheRangeTheSettingsOffer() {
        // Clamped rather than rejected: the number can arrive from a stepper or from an older stored blob,
        // and a rejected value would break a search the user can do nothing about.
        XCTAssertEqual(searchState(resultCount: 99).resultCount, 10)
        XCTAssertEqual(searchState(resultCount: 1).resultCount, 3)
        XCTAssertEqual(searchState(resultCount: 5).resultCount, 5)
    }

    func testTheCloudBodyCarriesTheClampedCountRatherThanTheStoredOne() async throws {
        let (search, transport) = searchTool(
            searchState(cloudRow(), credential: "k", resultCount: 99)
        )
        _ = try await search.execute(searchCall("rain in Paris"), context: armedContext)
        let fields = try RequestReader.bodyFields(try XCTUnwrap(transport.requests.first))
        let count = try XCTUnwrap(fields["max_results"] as? Int)
        XCTAssertEqual(count, 10, "the same number the settings screen offered, whatever was stored")
    }
}
