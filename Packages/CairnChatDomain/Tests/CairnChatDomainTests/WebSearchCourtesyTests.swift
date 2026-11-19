import Foundation
import XCTest
@testable import CairnChatDomain

/// Pacing and in-memory de-duplication.
///
/// The rule these tests hold is that the cache is memory-only and provider-scoped. A persisted search cache
/// would be a file of the user's questions written without asking, and a cache keyed on the query alone
/// would answer a question aimed at the user's own instance with somebody else's results.
final class WebSearchCourtesyTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func key(
        _ provider: UUID,
        query: String = "rain in Paris",
        safe: WebSearchSafeSearch = .moderate,
        range: WebSearchTimeRange? = nil,
        categories: [String] = [],
        language: String? = nil,
        count: Int = 5
    ) -> String {
        WebSearchCourtesy.key(
            providerID: provider, query: query, safeSearch: safe, timeRange: range,
            categories: categories, language: language, resultCount: count
        )
    }

    func testTheFirstRequestGoesImmediatelyAndTheNextOneWaits() {
        var courtesy = WebSearchCourtesy(minimumGap: 1.2, timeToLive: 300)
        XCTAssertEqual(courtesy.delayBefore(t0), 0)
        courtesy.noteRequest(at: t0)
        XCTAssertEqual(courtesy.delayBefore(t0), 1.2, accuracy: 0.001)
        XCTAssertEqual(courtesy.delayBefore(t0.addingTimeInterval(0.4)), 0.8, accuracy: 0.001)
        XCTAssertEqual(courtesy.delayBefore(t0.addingTimeInterval(5)), 0, "the wait expires on its own")
    }

    func testAnIdenticalQueryIsAnsweredFromMemoryInsideTheWindow() {
        var courtesy = WebSearchCourtesy(minimumGap: 0, timeToLive: 60)
        let found = [WebSearchResult(title: "Rain", url: "https://example.com/paris", snippet: "Wet.")]
        let cacheKey = key(first)
        XCTAssertNil(courtesy.cachedResults(for: cacheKey, now: t0))
        courtesy.remember(found, for: cacheKey, at: t0)
        XCTAssertEqual(courtesy.cachedResults(for: cacheKey, now: t0.addingTimeInterval(59)), found)
        XCTAssertNil(courtesy.cachedResults(for: cacheKey, now: t0.addingTimeInterval(61)), "it expires")
    }

    func testAnotherProvidersAnswerIsNeverServedForThisQuery() {
        var courtesy = WebSearchCourtesy(minimumGap: 0, timeToLive: 600)
        let found = [WebSearchResult(title: "Rain", url: "https://example.com/paris")]
        courtesy.remember(found, for: key(first), at: t0)
        XCTAssertNil(
            courtesy.cachedResults(for: key(second), now: t0),
            "the same words aimed at a different provider are a different question"
        )
    }

    /// A repeated question asked with different spacing or capitalisation is the same question, so it hits
    /// the same cache entry; anything that can change the answer gets its own key.
    func testNormalisationMakesARepeatedQuestionTheSameQuestion() {
        XCTAssertEqual(WebSearchCourtesy.normalize("  Rain   in  PARIS \n"), "rain in paris")
        XCTAssertEqual(WebSearchCourtesy.key(
            providerID: first, query: "  Rain   in  PARIS ", safeSearch: .moderate, timeRange: nil,
            categories: [], language: nil, resultCount: 5
        ), key(first))
    }

    func testAnythingThatChangesTheAnswerChangesTheKey() {
        let base = key(first)
        XCTAssertNotEqual(base, key(first, query: "snow in Paris"))
        XCTAssertNotEqual(base, key(first, safe: .strict))
        XCTAssertNotEqual(base, key(first, range: .month))
        XCTAssertNotEqual(base, key(first, categories: ["news"]))
        XCTAssertNotEqual(base, key(first, language: "fr"))
        XCTAssertNotEqual(base, key(first, count: 8))
    }

    func testTheCacheStaysBoundedAndDropsTheOldestFirst() {
        var courtesy = WebSearchCourtesy(minimumGap: 0, timeToLive: 600, entryCap: 3)
        for index in 0..<5 {
            courtesy.remember(
                [WebSearchResult(title: "\(index)", url: "https://example.com/\(index)")],
                for: key(first, query: "q\(index)"), at: t0
            )
        }
        XCTAssertEqual(courtesy.entries.count, 3)
        XCTAssertNil(courtesy.cachedResults(for: key(first, query: "q0"), now: t0))
        XCTAssertNotNil(courtesy.cachedResults(for: key(first, query: "q4"), now: t0))
    }

    /// The claim this struct exists to support: it is a value with a clock handed in, so it cannot hold a
    /// file, a socket, or a timer. `reset` is the whole surface for "forget what was searched", and it is
    /// the reason a search history cannot survive a settings change.
    func testResetForgetsBothTheCacheAndThePacing() {
        var courtesy = WebSearchCourtesy(minimumGap: 2, timeToLive: 600)
        let cacheKey = key(first)
        courtesy.remember([WebSearchResult(title: "Rain", url: "https://example.com/paris")], for: cacheKey, at: t0)
        courtesy.noteRequest(at: t0)
        XCTAssertEqual(courtesy.delayBefore(t0), 2)
        courtesy.reset()
        XCTAssertNil(courtesy.cachedResults(for: cacheKey, now: t0))
        XCTAssertEqual(courtesy.delayBefore(t0), 0)
        XCTAssertTrue(courtesy.entries.isEmpty)
    }
}
