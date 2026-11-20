import XCTest
@testable import CairnChatDomain

/// The Download tab's filter bar, proved as rules rather than as a screen.
///
/// Two failures are the reason this file exists. A chip that widens instead of narrowing promises a
/// capability the model does not have, and the person finds out when the model fails the turn. And a
/// search that answers "nothing here" to a name that is perfectly installable reads as a broken
/// screen rather than as a library Cairn has not curated. Neither is visible in a screenshot.
final class ModelCatalogFilterTests: XCTestCase {
    private func row(
        _ id: String,
        _ name: String,
        bytes: Int64? = nil,
        caps: [String] = [],
        provider: String? = nil,
        series: String? = nil,
        summary: String = "",
        rank: Int = 0,
        added: Int = 0,
        origin: ModelCatalogOrigin = .onDevice
    ) -> LocalCatalogRow {
        LocalCatalogRow(
            repoID: id, displayName: name, summary: summary, downloadBytes: bytes,
            capabilityLabels: caps, addedOn: Date(timeIntervalSince1970: TimeInterval(added)),
            provider: provider, series: series, sortOrder: rank, origin: origin
        )
    }

    private var library: [LocalCatalogRow] {
        [
            row("m/small-vision", "Small Vision", bytes: 1_000_000_000, caps: ["Vision"],
                provider: "Google", series: "Gemma 4", rank: 2, added: 20),
            row("m/big-tools", "Big Tools", bytes: 9_000_000_000, caps: ["Tools", "Vision"],
                provider: "Qwen", series: "Qwen 3.5", rank: 0, added: 10),
            row("m/mid-think", "Mid Think", bytes: 3_000_000_000, caps: ["Thinking"],
                provider: "OpenBMB", series: "MiniCPM5", rank: 1, added: 30),
            row("m/quiet", "Quiet Text", bytes: nil, provider: "Meta", series: "Llama 3.2",
                rank: 3, added: 40)
        ]
    }

    func testOneChipKeepsOnlyWhatStatesThatCapability() {
        XCTAssertEqual(
            ModelCatalogQuery.rows(library, filter: ModelCatalogFilter(capabilities: [.vision]))
                .map(\.id),
            ["m/big-tools", "m/small-vision"]
        )
    }

    /// Two chips are one narrower question, not two wider ones: the intersection, never the union.
    func testTwoChipsIntersectRatherThanAdd() {
        XCTAssertEqual(
            ModelCatalogQuery.rows(
                library,
                filter: ModelCatalogFilter(capabilities: [.vision, .tools])
            ).map(\.id),
            ["m/big-tools"]
        )
    }

    func testTakingAChipOffRestoresTheWholeList() {
        let twice = ModelCatalogFilter()
            .toggling(.audio)
            .toggling(.audio)
        XCTAssertTrue(twice.capabilities.isEmpty)
        XCTAssertEqual(ModelCatalogQuery.rows(library, filter: twice).count, library.count)
    }

    func testAnAudioChipFindsNothingRatherThanEverything() {
        // A capability nobody in this library publishes empties the list. That is the honest answer,
        // and the empty state is what has to say so.
        let rows = ModelCatalogQuery.rows(library, filter: ModelCatalogFilter(capabilities: [.audio]))
        XCTAssertEqual(rows.count, 0)
    }

    func testSearchMeansTheFamilyThePublisherAndTheDescription() {
        for needle in ["gemma", "GOOGLE", "m/small-vision", "minicpm", "vision"] {
            XCTAssertFalse(
                ModelCatalogQuery.rows(library, filter: ModelCatalogFilter(search: needle)).isEmpty,
                needle
            )
        }
        XCTAssertEqual(
            ModelCatalogQuery.rows(library, filter: ModelCatalogFilter(search: "  GEMMA  ")).map(\.id),
            ["m/small-vision"]
        )
    }

    func testSearchAndChipsNarrowTogether() {
        XCTAssertEqual(
            ModelCatalogQuery.rows(
                library,
                filter: ModelCatalogFilter(search: "vision", capabilities: [.tools])
            ).map(\.id),
            ["m/big-tools"]
        )
    }

    func testPopularUsesTheCuratedRankAndNotTheSize() {
        XCTAssertEqual(
            ModelCatalogQuery.rows(library, filter: ModelCatalogFilter(sort: .popular)).map(\.id),
            ["m/big-tools", "m/mid-think", "m/small-vision", "m/quiet"]
        )
    }

    func testNewestAndSizeOrdersAndTheUnstatedSizeNeverFirst() {
        XCTAssertEqual(
            ModelCatalogQuery.rows(library, filter: ModelCatalogFilter(sort: .newest)).map(\.id),
            ["m/quiet", "m/mid-think", "m/small-vision", "m/big-tools"]
        )
        // Nobody stated a size is not "zero bytes": it never leads the smallest order.
        XCTAssertEqual(
            ModelCatalogQuery.rows(library, filter: ModelCatalogFilter(sort: .smallest)).last?.id,
            "m/quiet"
        )
        XCTAssertEqual(
            ModelCatalogQuery.rows(library, filter: ModelCatalogFilter(sort: .largest)).first?.id,
            "m/big-tools"
        )
    }

    func testTheDownloadMenuOffersExactlyFourOrders() {
        XCTAssertEqual(
            LocalSortOrder.downloadOrders.map(\.label),
            ["Popular", "Newest", "Smallest download", "Largest"]
        )
    }

    func testClearingNarrowingKeepsTheChosenOrder() {
        var filter = ModelCatalogFilter(search: "gemma", capabilities: [.vision], sort: .largest)
        filter.clearNarrowing()
        XCTAssertTrue(filter.search.isEmpty)
        XCTAssertTrue(filter.capabilities.isEmpty)
        XCTAssertEqual(filter.sort, .largest)
        XCTAssertFalse(filter.isNarrowed)
    }
}
