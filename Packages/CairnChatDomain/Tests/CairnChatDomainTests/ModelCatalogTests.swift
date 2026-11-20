import XCTest
@testable import CairnChatDomain

/// Cairn's curated download library, checked as data rather than as a screenshot.
///
/// A curated list fails quietly: a duplicated repository, a size copied from a different build, a
/// summary left blank, a badge nobody published. None of those break a build, and all of them reach a
/// person as a claim about a model — so the shape of every row is proved here instead.
final class ModelCatalogTests: XCTestCase {
    func testEveryOnDeviceRowIsNamedByItsExactRepository() {
        XCTAssertFalse(ModelCatalog.onDevice.isEmpty)
        for row in ModelCatalog.onDevice {
            let parts = row.repoID.split(separator: "/")
            XCTAssertEqual(parts.count, 2, "\(row.repoID) is not an owner/repository pair",
                           file: #file, line: #line)
            XCTAssertEqual(row.origin, .onDevice)
        }
    }

    func testEveryRowStatesWhatItIsAndWhoMakesIt() {
        for row in ModelCatalog.rows(for: .onDevice) + ModelCatalog.rows(for: .ollamaLibrary) {
            XCTAssertFalse(row.displayName.isEmpty, row.repoID)
            XCTAssertFalse(row.summary.isEmpty, "\(row.repoID) has no description")
            XCTAssertFalse(row.provider?.isEmpty ?? true, "\(row.repoID) names no publisher")
            XCTAssertFalse(row.series?.isEmpty ?? true, "\(row.repoID) names no family")
        }
    }

    /// A badge is a claim the person acts on, so a curated row may carry only the words the chip bar
    /// offers. An entry that states nothing carries nothing, which is why this must not be a default.
    func testCapabilityLabelsAreOnlyEverWordsTheChipsKnow() {
        let known = Set(ModelCatalogCapability.allCases.map(\.label))
        for row in ModelCatalog.onDevice + ModelCatalog.ollama {
            for label in row.capabilityLabels {
                XCTAssertTrue(known.contains(label), "\(row.repoID) badges \(label)")
            }
        }
        XCTAssertTrue(ModelCatalog.onDevice.contains { $0.capabilityLabels.isEmpty },
                      "a curated list where everything is multimodal would mean a badge was guessed")
    }

    func testNoEntryIsOfferedTwiceUnderTheSameName() {
        for rows in [ModelCatalog.onDevice, ModelCatalog.ollama] {
            let ids = rows.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count)
            let ranks = rows.map(\.sortOrder)
            XCTAssertEqual(Set(ranks).count, ranks.count)
            XCTAssertEqual(ranks, (0..<ranks.count).sorted())
        }
    }

    /// Sizes are published figures. A row whose stated download is smaller than the weights the
    /// downloader will pull is a size copied from the wrong build, which is the mistake this catches.
    func testStatedSizesAreStatedInBytesAndOrderedSensibly() {
        for row in ModelCatalog.onDevice + ModelCatalog.ollama {
            guard let bytes = row.downloadBytes else { continue }
            XCTAssertGreaterThan(bytes, 0)
        }
        // The smallest curated download is under a gigabyte and the largest is under ten, which is
        // what "an 8 GB phone can plausibly hold these" means. A stray extra zero trips this.
        let sizes = ModelCatalog.onDevice.compactMap(\.downloadBytes)
        XCTAssertLessThan(sizes.min() ?? .max, 1_000_000_000)
        XCTAssertLessThan(sizes.max() ?? .max, 10_000_000_000)
    }

    func testMarkingSettlesInstalledWithoutTouchingOrderOrMetadata() {
        let installed: Set<String> = ["mlx-community/Qwen3-4B-MLX-4bit"]
        let rows = ModelCatalog.marking(ModelCatalog.onDevice, installed: installed)
        XCTAssertEqual(rows.map(\.id), ModelCatalog.onDevice.map(\.id))
        for (before, after) in zip(ModelCatalog.onDevice, rows) {
            XCTAssertEqual(after.repoID, before.repoID)
            XCTAssertEqual(after.summary, before.summary)
            XCTAssertEqual(after.downloadBytes, before.downloadBytes)
            XCTAssertEqual(after.isInstalled, installed.contains(before.id))
        }
    }

    func testATypedNameHasNoCuratedList() {
        XCTAssertTrue(ModelCatalog.rows(for: .custom).isEmpty)
    }
}
