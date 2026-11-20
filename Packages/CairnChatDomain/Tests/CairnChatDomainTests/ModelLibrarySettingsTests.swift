import XCTest
@testable import CairnChatDomain

/// The switch that decides whether the Models screen offers the curated library.
///
/// A settings row written by an older build has no key for this. If that read as "off", upgrading
/// would quietly remove a screen, and the person would have no way to know they had not turned it off
/// themselves — which is why the field is optional and why the missing key decodes to the shipped
/// answer rather than to a failure.
final class ModelLibrarySettingsTests: XCTestCase {
    func testTheLibraryIsShownUntilThePersonSaysOtherwise() {
        XCTAssertTrue(AppSettings.default.downloadCatalogIsShown)
        XCTAssertNil(AppSettings.default.showsDownloadCatalog)
    }

    func testTurningItOffReturnsANewValueRatherThanMutatingTheOldOne() {
        let before = AppSettings.default
        let after = before.setDownloadCatalogShown(false)
        XCTAssertFalse(after.downloadCatalogIsShown)
        XCTAssertTrue(before.downloadCatalogIsShown)
        XCTAssertEqual(after.themeID, before.themeID)
    }

    func testASettingsRowFromBeforeTheSwitchStillDecodes() throws {
        let legacy = #"{"defaultChatConfig":{},"themeID":"trailhead","appearance":"system","showsGenerationStats":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.downloadCatalogIsShown)
        XCTAssertEqual(decoded.themeID, "trailhead")
    }

    func testWeightsAreNotAllowedUntilThePersonGrantsThem() {
        XCTAssertFalse(AppSettings.default.modelDownloadsAreAllowed)
        XCTAssertNil(AppSettings.default.modelDownloadsAllowed)
        let granted = AppSettings.default.setModelDownloadsAllowed(true)
        XCTAssertTrue(granted.modelDownloadsAreAllowed)
        XCTAssertFalse(AppSettings.default.modelDownloadsAreAllowed,
                       "granting must not mutate the value the caller started from")
    }

    func testAGrantedAcknowledgementSurvivesAWriteAndReadRoundTrip() throws {
        let data = try JSONEncoder().encode(AppSettings.default.setModelDownloadsAllowed(true))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.modelDownloadsAreAllowed)
    }

    /// The two switches default in opposite directions on purpose: showing a list asks nothing of
    /// anyone, and a gigabyte of weights leaving the device does. A row written before either key
    /// existed — which is every row on a phone that has had Cairn since before this screen — must not
    /// silently grant the traffic.
    func testALegacyRowNeitherHidesTheLibraryNorGrantsTheTraffic() throws {
        let legacy = #"{"defaultChatConfig":{},"themeID":"trailhead","appearance":"system","showsGenerationStats":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.downloadCatalogIsShown)
        XCTAssertFalse(decoded.modelDownloadsAreAllowed)
        XCTAssertNil(decoded.showsDownloadCatalog)
        XCTAssertNil(decoded.modelDownloadsAllowed)
    }
}
