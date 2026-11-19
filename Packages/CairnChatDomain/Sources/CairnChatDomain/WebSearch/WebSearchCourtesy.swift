import Foundation

/// The pacing and in-memory de-duplication in front of a search provider.
///
/// Two reasons, one honest and one practical. DuckDuckGo's HTML endpoint is shared, and a tool loop can
/// fire several searches inside one turn — a model that searches five times in two seconds is one bad turn
/// away from the endpoint refusing every Cairn user. SearXNG instances are usually somebody's small box,
/// often the same box as the model server, and hammering it takes down the thing generating the answer.
///
/// The cache is **memory only, deliberately**. Persisted search results are a record of what the user asked
/// for, written to disk without being asked, and that is exactly the kind of side file a local-first app
/// should not create quietly. It is a struct, so it is trivially testable and holds no lock.
public struct WebSearchCourtesy: Sendable, Equatable {
    /// One cached answer. Internal, and never written anywhere but memory.
    struct Entry: Sendable, Equatable {
        var key: String
        var at: Date
        var results: [WebSearchResult]
    }

    /// The smallest interval between two requests to the same provider.
    public var minimumGap: TimeInterval
    /// How long a repeated identical query may be answered from memory.
    public var timeToLive: TimeInterval
    /// How many answers memory holds. A tool loop can produce many distinct queries in one long session;
    /// unbounded memory for a cache is its own bug.
    public var entryCap: Int

    public private(set) var lastRequestAt: Date?
    /// Internal on purpose: the cache is an implementation detail, and exposing `Entry` would put a public
    /// face on something that only exists to answer one identical query twice.
    private(set) var entries: [Entry]

    public init(
        minimumGap: TimeInterval = 1.2,
        timeToLive: TimeInterval = 300,
        entryCap: Int = 24
    ) {
        self.minimumGap = max(0, minimumGap)
        self.timeToLive = max(0, timeToLive)
        self.entryCap = max(1, entryCap)
        self.entries = []
    }

    public static let `default` = WebSearchCourtesy()

    /// Seconds to hold before the next request, or 0 when it is fine to go now.
    ///
    /// Returning a number rather than a Bool is what lets the caller wait instead of failing: a search that
    /// arrives 200 ms early should be a slightly later search, not a turn that says it could not search.
    public func delayBefore(_ now: Date) -> TimeInterval {
        guard let last = lastRequestAt else { return 0 }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= minimumGap ? 0 : minimumGap - elapsed
    }

    public mutating func noteRequest(at now: Date) { lastRequestAt = now }

    /// A stored answer for this exact query and provider, or nil.
    ///
    /// Expired entries are dropped on read rather than on a timer, because a value type has no timer to
    /// hold and a stale answer must never be served quietly.
    public func cachedResults(for key: String, now: Date) -> [WebSearchResult]? {
        guard let hit = entries.first(where: { $0.key == key }),
              now.timeIntervalSince(hit.at) <= timeToLive
        else { return nil }
        return hit.results
    }

    public mutating func remember(
        _ results: [WebSearchResult], for key: String, at now: Date
    ) {
        entries.removeAll { $0.key == key || now.timeIntervalSince($0.at) > timeToLive }
        entries.append(Entry(key: key, at: now, results: results))
        // Oldest first: `entries` is append-only, so the head is the least useful thing to keep.
        while entries.count > entryCap { entries.removeFirst() }
    }

    public mutating func reset() {
        entries.removeAll()
        lastRequestAt = nil
    }

    /// A cache key that covers everything that can change the answer.
    ///
    /// Leaving the provider out would serve DuckDuckGo's results for a query the user expects from their own
    /// instance, which is the one cache mistake worth being careful about here.
    public static func key(
        providerID: UUID,
        query: String,
        safeSearch: WebSearchSafeSearch,
        timeRange: WebSearchTimeRange?,
        categories: [String],
        language: String?,
        resultCount: Int
    ) -> String {
        [
            providerID.uuidString,
            normalize(query),
            String(safeSearch.rawValue),
            timeRange?.rawValue ?? "-",
            categories.sorted().joined(separator: ","),
            language ?? "-",
            String(resultCount),
        ].joined(separator: "\u{1F}")
    }

    /// Case and whitespace are noise for search purposes, so a repeated question asked with different
    /// capitalisation is the same question.
    public static func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
