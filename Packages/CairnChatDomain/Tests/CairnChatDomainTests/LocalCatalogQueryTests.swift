import XCTest
@testable import CairnChatDomain

/// Narrowing and ordering the on-device library.
///
/// The library was unreachable for a while because there was no screen for it at all; once there is
/// one, the next way it fails is a filter that hides the only model that would have fitted, or a
/// search that answers "nothing here" to a repository the person typed exactly. Both are invisible
/// in a screenshot, so they are proved here.
final class LocalCatalogQueryTests: XCTestCase {
    private func row(
        _ repo: String,
        _ name: String,
        bytes: Int64?,
        capabilities: [String] = [],
        added: Int = 0
    ) -> LocalCatalogRow {
        LocalCatalogRow(
            repoID: repo,
            displayName: name,
            downloadBytes: bytes,
            capabilityLabels: capabilities,
            addedOn: Date(timeIntervalSince1970: TimeInterval(added))
        )
    }

    private var library: [LocalCatalogRow] {
        [
            row("small/capable", "Small Capable", bytes: 2_000_000_000, capabilities: ["Tools"], added: 10),
            row("big/plain", "Big Plain", bytes: 9_000_000_000, added: 30),
            row("mid/vision", "Mid Vision", bytes: 3_000_000_000, capabilities: ["Vision"], added: 20),
            row("mystery/unknown", "Mystery Size", bytes: nil, capabilities: ["Tools"], added: 40)
        ]
    }

    func testTheAllChipKeepsEverything() {
        XCTAssertEqual(LocalCatalogQuery.rows(library).count, 4)
    }

    func testACapabilityChipKeepsOnlyWhatPublishesThatCapability() {
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, chip: .visual).map(\.repoID),
            ["mid/vision"]
        )
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, chip: .capable).map(\.repoID),
            ["small/capable", "mystery/unknown"]
        )
    }

    /// "Under 4 GB" means the ones that fit, and it keeps the entry whose size nobody stated: unknown
    /// is not "too big", and dropping it would hide a model the person could well download.
    func testTheSizeChipDropsWhatIsTooBigAndKeepsWhatIsUnstated() {
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, chip: .small).map(\.repoID),
            ["small/capable", "mid/vision", "mystery/unknown"]
        )
    }

    func testSearchMatchesTheRepositoryAndNotOnlyTheDisplayName() {
        // Someone typing a repository name means the repository, and a display name that does not
        // contain it is not a reason to answer "nothing here".
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, search: "small/cap").map(\.repoID),
            ["small/capable"]
        )
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, search:  "  VISION  ").map(\.repoID),
            ["mid/vision"]
        )
    }

    func testSmallestSortPutsAnUnstatedSizeLastRatherThanFirst() {
        // Zero bytes is not what "no size published" means; sorting it first would promise the
        // smallest download in the list for the one entry nobody sized.
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, sort: .smallest).map(\.repoID),
            ["small/capable", "mid/vision", "big/plain", "mystery/unknown"]
        )
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, sort: .largest).map(\.repoID).first,
            "mystery/unknown"
        )
    }

    func testNewestAndNameOrderTheListTheyClaim() {
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, sort: .newest).map(\.repoID),
            ["mystery/unknown", "big/plain", "mid/vision", "small/capable"]
        )
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, sort: .name).map(\.displayName).first,
            "Big Plain"
        )
    }

    func testRecommendedPutsASmallCapableModelFirst() {
        XCTAssertEqual(
            LocalCatalogQuery.rows(library, sort: .recommended).map(\.repoID).first,
            "small/capable"
        )
    }

    /// A repository typed that Cairn's short list does not carry is offered as itself, because the
    /// curated list is short and Hugging Face is not.
    func testATypedRepositoryIsOfferedWhenTheListDoesNotCarryIt() {
        XCTAssertEqual(
            LocalCatalogQuery.unlistedRepoID(search: "some-org/some-model-GGUF", in: library),
            "some-org/some-model-GGUF"
        )
        XCTAssertNil(LocalCatalogQuery.unlistedRepoID(search: "small/capable", in: library))
        XCTAssertNil(LocalCatalogQuery.unlistedRepoID(search: "justwords", in: library))
        XCTAssertNil(LocalCatalogQuery.unlistedRepoID(search: "a/b/c", in: library))
        XCTAssertNil(LocalCatalogQuery.unlistedRepoID(search: "org /repo", in: library))
        XCTAssertNil(LocalCatalogQuery.unlistedRepoID(search: "", in: library))
    }

    func testATransferReportsProgressOnlyWhenATotalWasStated() {
        XCTAssertEqual(
            LocalTransferState.running(doneBytes: 500, totalBytes: 1_000).fraction,
            0.5
        )
        XCTAssertNil(LocalTransferState.running(doneBytes: 500, totalBytes: nil).fraction)
        XCTAssertNil(LocalTransferState.queued.fraction)
        XCTAssertTrue(LocalTransferState.queued.isInFlight)
        XCTAssertTrue(LocalTransferState.running(doneBytes: 1, totalBytes: 9).isInFlight)
        XCTAssertFalse(LocalTransferState.stopped.isInFlight)
        XCTAssertFalse(LocalTransferState.installed(bytes: 8).isInFlight)
        XCTAssertEqual(LocalTransferState.failed("no space left").label, "no space left")
    }
}
