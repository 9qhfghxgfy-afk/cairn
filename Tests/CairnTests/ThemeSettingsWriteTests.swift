import SwiftUI
import XCTest
import CairnChatDomain
import CairnAppUI
@testable import CairnPersistence

/// Every settings write the settings object makes, proved to land where it claims — and proved not to
/// disturb the two values a window is painted from.
///
/// Two bugs meet in this file, and neither one was ever visible to a compiler.
///
/// The first is the write. `AppSettings` has two shapes of setter: a mutating one, and one that returns a
/// **new** value (`setModelDownloadsAllowed`, `setDownloadCatalogShown`) because the stored key is optional
/// and the whole copy is what travels to the store. A wrapper written `mutate { $0.setX(v) }` compiles and
/// runs against either shape; against the copy-returning one it discards the returned value —
/// `@discardableResult` makes that legal and silent — and writes nothing at all. The download
/// acknowledgement was in that group. Tapping "Allow & Download" granted nothing, so the download refused
/// to start, the Download tab printed its notice line, and that line appearing inside the list's own
/// content tore down the sheet the person was standing in. The button was not broken; it was writing into
/// a copy nobody kept.
///
/// The second is what a write is allowed to disturb. Observation tracks a **property**, not a field inside
/// a struct, so a view that reads `settings` to resolve its paint is invalidated by every settings write in
/// the app — including one that changes nothing on screen. The paint is therefore republished only when the
/// theme or the appearance moves. Both halves are held here: an unrelated write leaves the paint and the
/// tool signals exactly where they were, and a theme change still moves everything it should.
@MainActor
final class ThemeSettingsWriteTests: XCTestCase {
    private func makeStore() throws -> SwiftDataStore { try SwiftDataStore(inMemory: true) }

    private func theme(_ id: String = "dusk", _ appearance: AppearanceMode = .system) -> ThemeModel {
        ThemeModel(settings: AppSettings(themeID: id, appearance: appearance))
    }

    // MARK: The writes land

    /// The acknowledgement the Download sheet's own button grants — asserted first and alone, because
    /// everything downstream of it (the download, the badge, the notice, the dismissed sheet) followed
    /// from this one value not being written.
    func testGrantingModelDownloadsWritesTheAcknowledgement() {
        let model = theme()
        XCTAssertFalse(model.settings.modelDownloadsAreAllowed, "weights are off until granted")
        model.setModelDownloadsAllowed(true)
        XCTAssertTrue(model.settings.modelDownloadsAreAllowed,
                      "the tap that says 'allow' has to leave an allowed record behind")
        model.setModelDownloadsAllowed(false)
        XCTAssertFalse(model.settings.modelDownloadsAreAllowed, "and take it back the same way")
    }

    func testTheCataloguePreferenceIsWrittenAndNotOnlyRememberedOnScreen() {
        let model = theme()
        XCTAssertTrue(model.settings.downloadCatalogIsShown, "the curated library defaults to on")
        model.setDownloadCatalogShown(false)
        XCTAssertFalse(model.settings.downloadCatalogIsShown)
    }

    /// The store, not just memory: a settings value that survives only inside the object holding it is the
    /// exact shape of the bug this file exists for.
    func testTheWeightsAcknowledgementSurvivesTheStoreItIsWrittenTo() throws {
        let store = try makeStore()
        let model = ThemeModel(storing: store)
        XCTAssertFalse(model.settings.modelDownloadsAreAllowed)
        model.setModelDownloadsAllowed(true)
        let written = try store.appSettings()
        XCTAssertTrue(written.modelDownloadsAreAllowed,
                      "a granted acknowledgement must be on disk before the next launch reads it")

        let reader = ThemeModel(storing: store)
        XCTAssertTrue(reader.settings.modelDownloadsAreAllowed,
                      "a second settings object reading the same store must see the grant")
    }

    func testTheCataloguePreferenceSurvivesTheStoreToo() throws {
        let store = try makeStore()
        let model = ThemeModel(storing: store)
        model.setDownloadCatalogShown(false)
        let written = try store.appSettings()
        XCTAssertFalse(written.downloadCatalogIsShown)
    }

    /// The mutating-shaped setters, checked beside the copy-returning ones so the two shapes stay honest
    /// side by side: a wrapper that reads like its neighbour has to behave like it too.
    func testTheMutatingSettersStillWriteTheirOwnValues() {
        let model = theme()
        XCTAssertTrue(model.settings.showsGenerationStats)
        model.setShowsGenerationStats(false)
        XCTAssertFalse(model.settings.showsGenerationStats)

        model.setOutboundWebAllowed(true)
        XCTAssertTrue(model.settings.outboundWebAllowed)
        model.setOutboundWebAllowed(false)
        XCTAssertFalse(model.settings.outboundWebAllowed)

        model.select(themeID: "trailhead")
        XCTAssertEqual(model.settings.themeID, "trailhead")
        model.select(appearance: .dark)
        XCTAssertEqual(model.settings.appearance, .dark)
    }

    // MARK: What a write may disturb

    /// The tap this file was written for, read from the other side: granting weights changes a permission
    /// and nothing a window is drawn from.
    func testGrantingWeightsMovesNeitherThePaintNorTheToolSignals() {
        let model = theme()
        let paint = model.chrome
        let signals = model.toolSignals
        model.setModelDownloadsAllowed(true)
        XCTAssertEqual(model.chrome, paint, "an acknowledgement is not a colour")
        XCTAssertEqual(model.toolSignals, signals, "and it is not a tool answer either")
        XCTAssertTrue(model.settings.modelDownloadsAreAllowed, "while still moving the setting itself")
    }

    func testTheCataloguePreferenceMovesNeitherThePaintNorTheToolSignals() {
        let model = theme("dusk", .light)
        let paint = model.chrome
        let signals = model.toolSignals
        model.setDownloadCatalogShown(false)
        XCTAssertEqual(model.chrome, paint)
        XCTAssertEqual(model.toolSignals, signals)
    }

    /// A window asks `CairnChromeStyle` the same question the root asks. If an unrelated settings write
    /// moved the answer, every window wearing it would be re-evaluated — and a window chain rebuilt while a
    /// sheet is open takes the sheet, and anything stacked under it, down with it.
    func testTheTokensARootAndItsSheetsResolveAreUntouchedByAnUnrelatedWrite() {
        let model = theme("dusk", .dark)
        let before = CairnChromeStyle.tokens(for: model, deviceScheme: .light)
        let pinned = model.colorScheme
        model.setModelDownloadsAllowed(true)
        model.setDownloadCatalogShown(false)
        XCTAssertEqual(CairnChromeStyle.tokens(for: model, deviceScheme: .light), before)
        XCTAssertEqual(model.colorScheme, pinned, "and the window keeps the half it was told to pin")
    }

    // MARK: The writes that must still work

    func testAThemeOrAppearanceChangeStillMovesThePaint() {
        let model = theme("dusk", .light)
        model.select(themeID: "trailhead")
        XCTAssertEqual(model.chrome.palette.id, "trailhead")
        XCTAssertEqual(CairnChromeStyle.palette(for: model).id, "trailhead")

        model.select(appearance: .dark)
        XCTAssertEqual(model.chrome.appearance, .dark)
        XCTAssertEqual(CairnChromeStyle.appearance(for: model), .dark)
        XCTAssertEqual(CairnChromeStyle.pinnedScheme(for: model), .dark)
    }

    func testTheTwoToolAnswersStillMoveTheSignalsAndOnlyThem() {
        let model = theme()
        let paint = model.chrome
        model.setOutboundWebAllowed(true)
        XCTAssertTrue(model.toolSignals.webToolsAllowed)
        XCTAssertFalse(model.toolSignals.showsGenerationStats, "one switch must not move the other")

        model.setShowsGenerationStats(false)
        XCTAssertFalse(model.toolSignals.showsGenerationStats)
        XCTAssertTrue(model.toolSignals.webToolsAllowed, "and must not reset it")

        XCTAssertEqual(model.chrome, paint, "neither switch is a paint answer")
    }
}
