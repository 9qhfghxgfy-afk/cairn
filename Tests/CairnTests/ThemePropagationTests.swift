import SwiftUI
import XCTest
import CairnChatDomain
import CairnAppUI
@testable import CairnPersistence

/// The rule every Cairn window is painted with, checked where it is decided.
///
/// The phone complaint was that a theme change moved the chat and left the sheets behind. The cause was
/// not one broken screen but many screens each resolving their own paint, with the environment default —
/// one fixed dark palette — behind any window that forgot to. So the rule lives in `CairnChromeStyle` and
/// these tests hold it: root and presentation resolve the same tokens from the same settings, an
/// unwired window still gets the shipped identity, and a presentation with no theme overrides nothing
/// rather than quietly choosing a look of its own.
///
/// Pixels are not asserted; a `Color` has no readable value to compare, and a screenshot test cannot say
/// "this window asked the same question as the root". Asking the question identically is the fix.
@MainActor
final class ThemePropagationTests: XCTestCase {

    private func theme(_ id: String, _ appearance: AppearanceMode = .system) -> ThemeModel {
        ThemeModel(settings: AppSettings(themeID: id, appearance: appearance))
    }

    /// A sheet, a stack inside it, and the root all read this one function — so if it resolves the
    /// settings correctly, they cannot disagree.
    func testAWindowAndAPresentationResolveTheSameTokensAsTheSettingsObject() {
        for palette in ThemeProvider.themes {
            let settings = theme(palette.id)
            for deviceScheme in [ColorScheme.light, .dark] {
                let resolved = CairnChromeStyle.tokens(for: settings, deviceScheme: deviceScheme)
                XCTAssertEqual(
                    resolved, palette.tokens(for: deviceScheme),
                    "\(palette.id) at \(deviceScheme) must resolve to that theme's own half"
                )
                XCTAssertEqual(
                    CairnChromeStyle.palette(for: settings).id, palette.id,
                    "\(palette.id) must not resolve to another theme"
                )
            }
        }
    }

    func testAChosenAppearanceIsCarriedIntoEveryWindow() {
        // A user who pins Light on a dark device must get the light half everywhere, including a sheet
        // whose own window would otherwise follow the device.
        let pinned = theme("dusk", .light)
        XCTAssertEqual(
            CairnChromeStyle.tokens(for: pinned, deviceScheme: .dark),
            CairnPalette.dusk.light
        )
        XCTAssertEqual(CairnChromeStyle.pinnedScheme(for: pinned), .light)

        let followed = theme("dusk", .system)
        XCTAssertNil(CairnChromeStyle.pinnedScheme(for: followed), "follow the device overrides nothing")
        XCTAssertEqual(
            CairnChromeStyle.tokens(for: followed, deviceScheme: .dark), CairnPalette.dusk.dark
        )
    }

    /// Nothing wired — a preview, a test host, a root whose store has not resolved — still paints, and
    /// paints the identity the app shipped with.
    func testAnUnwiredWindowPaintsTheShippedIdentityAndPinsNothing() {
        XCTAssertEqual(CairnChromeStyle.palette(for: nil).id, AppSettings.defaultThemeID)
        XCTAssertEqual(CairnChromeStyle.appearance(for: nil), .system)
        XCTAssertNil(CairnChromeStyle.pinnedScheme(for: nil))
        XCTAssertEqual(
            CairnChromeStyle.tokens(for: nil, deviceScheme: .dark), CairnPalette.trailhead.dark
        )
        XCTAssertEqual(
            CairnChromeStyle.tokens(for: nil, deviceScheme: .light), CairnPalette.trailhead.light
        )
    }

    /// The accent is what a user notices first, so propagation is only real if a different theme actually
    /// changes it, and if the value a window paints is the theme's own.
    func testTheAccentFollowsTheThemeRatherThanStayingOneColour() {
        XCTAssertNotEqual(
            CairnChromeStyle.tokens(for: theme("dusk"), deviceScheme: .dark).accent,
            CairnChromeStyle.tokens(for: theme("quartz"), deviceScheme: .dark).accent,
            "two themes that paint the same accent are not two themes"
        )
        for palette in ThemeProvider.themes {
            for (deviceScheme, half) in [(ColorScheme.dark, palette.dark), (.light, palette.light)] {
                XCTAssertEqual(
                    CairnChromeStyle.tokens(for: theme(palette.id), deviceScheme: deviceScheme).accent,
                    half.accent,
                    "\(palette.id): the accent a window paints has to be that theme's own"
                )
            }
        }
    }

    /// A theme change is a settings write, and every window has to follow it — so the rule is read from
    /// the live object, not from a value captured at launch.
    func testAStoredThemeChangeMovesThePaintOfEveryWindow() throws {
        let store = try SwiftDataStore(inMemory: true)
        let settings = ThemeModel(storing: store)
        let before = CairnChromeStyle.tokens(for: settings, deviceScheme: .light)
        settings.select(themeID: "quartz")
        settings.select(appearance: .dark)
        let after = CairnChromeStyle.tokens(for: settings, deviceScheme: .light)

        XCTAssertNotEqual(before, after, "a theme change that changes nothing is not a change")
        XCTAssertEqual(after, CairnPalette.quartz.dark, "the pinned half wins over the device")
        XCTAssertEqual(
            CairnChromeStyle.tokens(for: ThemeModel(storing: store), deviceScheme: .light),
            after,
            "and the same paint is what a relaunched window resolves"
        )
    }
}
