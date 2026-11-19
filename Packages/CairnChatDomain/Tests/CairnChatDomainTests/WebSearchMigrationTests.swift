import Foundation
import XCTest
@testable import CairnChatDomain

/// Importing the legacy single SearXNG address into a provider row.
///
/// This is the upgrade path that can hurt the most: the person who already ran an instance is the person
/// who should least lose it on a version bump, and the failure mode is silent — search keeps working, just
/// from somewhere else. So the assertions are that the row exists, is active, and survives being run twice.
final class WebSearchMigrationTests: XCTestCase {
    func testNothingToImportChangesNothing() {
        for value in [nil, "", "   "] {
            var settings = WebSearchSettings.default
            XCTAssertFalse(WebSearchMigration.importLegacySearxngURL(value, into: &settings))
            XCTAssertEqual(settings.providerCount, 1)
            XCTAssertEqual(settings.activeProvider.kind, .duckDuckGo)
        }
    }

    func testAnExistingAddressBecomesARowAndStaysTheActiveProvider() throws {
        var settings = WebSearchSettings.default
        XCTAssertTrue(
            WebSearchMigration.importLegacySearxngURL("http://192.168.1.20:8888", into: &settings)
        )
        XCTAssertEqual(settings.providerCount, 2, "the built-in row is still there")
        let imported = try XCTUnwrap(settings.allProviders.first { $0.kind == .searxng })
        XCTAssertEqual(imported.baseURLString, "http://192.168.1.20:8888")
        XCTAssertEqual(imported.networkClass, .privateLan)
        XCTAssertTrue(imported.usesPlaintext, "and the row says so")
        XCTAssertEqual(settings.activeProvider.id, imported.id, "the upgrade must not move their queries")
    }

    func testImportingTwiceAddsOneRow() {
        var settings = WebSearchSettings.default
        let address = "https://search.example.com/searxng"
        XCTAssertTrue(WebSearchMigration.importLegacySearxngURL(address, into: &settings))
        XCTAssertFalse(WebSearchMigration.importLegacySearxngURL(address, into: &settings))
        XCTAssertEqual(settings.allProviders.filter { $0.kind == .searxng }.count, 1)
    }

    /// A trailing slash is the same instance. Comparing the parsed address rather than the string is what
    /// keeps a paste from producing a second row.
    func testTheSameAddressWithADifferentTrailingSlashIsNotADuplicate() {
        var settings = WebSearchSettings.default
        XCTAssertTrue(WebSearchMigration.importLegacySearxngURL("https://search.example.com", into: &settings))
        XCTAssertFalse(
            WebSearchMigration.importLegacySearxngURL("https://search.example.com/", into: &settings)
        )
        XCTAssertEqual(settings.allProviders.filter { $0.kind == .searxng }.count, 1)
    }

    /// An address that cannot be imported is left where it was, because dropping it would lose the user's
    /// only record of their own instance.
    func testAnUnusableAddressIsLeftAlone() {
        var settings = WebSearchSettings.default
        for value in ["not-an-address", "http://search.example.com", "https://user:pw@search.example.com"] {
            XCTAssertFalse(
                WebSearchMigration.importLegacySearxngURL(value, into: &settings),
                "\(value) must not become a row"
            )
            XCTAssertEqual(settings.providerCount, 1)
            XCTAssertEqual(settings.activeProvider.kind, .duckDuckGo)
        }
    }

    func testARowIsNamedAfterTheInstanceNotJustTheSoftware() {
        XCTAssertEqual(WebSearchMigration.suggestedName(forHost: "search.example.com"), "SearXNG — search")
        XCTAssertEqual(WebSearchMigration.suggestedName(forHost: "www.search.example.com"), "SearXNG — search")
        XCTAssertEqual(WebSearchMigration.suggestedName(forHost: "box.local"), "SearXNG — box")
        XCTAssertEqual(WebSearchMigration.suggestedName(forHost: "192.168.1.20"), "SearXNG (LAN)")
        XCTAssertEqual(WebSearchMigration.suggestedName(forHost: ""), "SearXNG")
    }

    func testMigratedSettingsStillRoundTripThroughJSON() throws {
        var settings = WebSearchSettings.default
        XCTAssertTrue(WebSearchMigration.importLegacySearxngURL("http://127.0.0.1:8888", into: &settings))
        let blob = try JSONEncoder().encode(settings)
        let revived = try JSONDecoder().decode(WebSearchSettings.self, from: blob)
        XCTAssertEqual(revived, settings)
        XCTAssertNil(revived.revertNotice)
    }
}
