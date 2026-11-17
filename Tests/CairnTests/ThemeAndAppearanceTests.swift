import XCTest
import CairnChatDomain
import CairnAppUI
@testable import CairnPersistence

/// P2 themes: every theme has two halves, the appearance picks one, and the choice survives a relaunch.
///
/// These run in the Xcode target because `Color` needs a real SwiftUI runtime, and they assert the
/// *rules* rather than the pixels: which half is chosen, that both halves exist and differ, and that
/// the stored id is what comes back after a relaunch.
@MainActor
final class ThemeAndAppearanceTests: XCTestCase {

    func testEveryThemeCarriesTwoDifferentHalves() {
        XCTAssertEqual(ThemeProvider.themes.count, 4, "the picker would otherwise grow silently")
        for palette in ThemeProvider.themes {
            XCTAssertFalse(palette.light.isDark, "\(palette.id) light half")
            XCTAssertTrue(palette.dark.isDark, "\(palette.id) dark half")
            XCTAssertNotEqual(
                palette.light.canvas, palette.dark.canvas,
                "\(palette.id) must not offer one appearance twice"
            )
            XCTAssertNotEqual(palette.light.accent, palette.dark.accent)
            // The preview card has to show both roles distinctly in both halves.
            XCTAssertNotEqual(palette.light.userBubble, palette.light.assistantBubble)
            XCTAssertNotEqual(palette.dark.userBubble, palette.dark.assistantBubble)
        }
    }

    func testThemeIDsAreUniqueAndTheDefaultResolves() {
        let ids = ThemeProvider.themes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.contains(AppSettings.defaultThemeID))
        XCTAssertEqual(
            ThemeProvider.theme(id: "a-theme-this-build-does-not-know").id,
            AppSettings.defaultThemeID,
            "a stored id from another build must not leave the app with no colours"
        )
    }

    func testAppearancePinsOrFollowsTheDevice() {
        XCTAssertNil(ThemeProvider.pinnedScheme(.system), "system must override nothing")
        XCTAssertEqual(ThemeProvider.pinnedScheme(.light), .light)
        XCTAssertEqual(ThemeProvider.pinnedScheme(.dark), .dark)
        XCTAssertEqual(
            ThemeProvider.resolveScheme(appearance: .system, deviceScheme: .dark), .dark
        )
        XCTAssertEqual(
            ThemeProvider.resolveScheme(appearance: .light, deviceScheme: .dark), .light,
            "a pinned appearance wins over the device"
        )
    }

    func testTokensPickTheResolvedHalf() {
        let passage = CairnPalette.passage
        XCTAssertEqual(
            ThemeProvider.tokens(themeID: "passage", appearance: .light, deviceScheme: .dark),
            passage.light
        )
        XCTAssertEqual(
            ThemeProvider.tokens(themeID: "passage", appearance: .system, deviceScheme: .dark),
            passage.dark
        )
        XCTAssertEqual(
            ThemeProvider.tokens(themeID: "nope", appearance: .system, deviceScheme: .light),
            CairnPalette.trailhead.light
        )
    }

    func testSwatchesNameCanvasSurfaceAccent() {
        for palette in ThemeProvider.themes {
            for tokens in [palette.light, palette.dark] {
                XCTAssertEqual(tokens.swatches, [tokens.canvas, tokens.surface, tokens.accent])
                XCTAssertEqual(tokens.swatches.count, 3)
            }
        }
    }

    func testThemeAppearanceAndDefaultConfigSurviveARelaunchAsOneRow() throws {
        let store = try SwiftDataStore(inMemory: true)
        let theme = ThemeModel(storing: store)
        XCTAssertEqual(theme.settings, .default, "no row reads as the shipped defaults")

        theme.select(themeID: "quartz")
        theme.select(appearance: .dark)
        theme.saveDefaultConfig(
            ChatConfig(persona: "Be brief.", sampling: SamplingConfig(topP: 0.5))
        )
        XCTAssertNil(theme.lastError)

        let reopened = ThemeModel(storing: store)
        XCTAssertEqual(reopened.settings.themeID, "quartz")
        XCTAssertEqual(reopened.settings.appearance, .dark)
        XCTAssertEqual(reopened.palette.id, "quartz")
        XCTAssertEqual(reopened.settings.defaultChatConfig.persona, "Be brief.")
        XCTAssertEqual(reopened.settings.configuredOptionCount, 1)
        XCTAssertTrue(reopened.settings.hasConfiguredDefaults)
        XCTAssertEqual(
            reopened.tokens(deviceScheme: .dark),
            ThemeProvider.tokens(themeID: "quartz", appearance: .dark, deviceScheme: .light)
        )
    }

    /// The Default Configuration seeds a chat that starts after it was saved, and never reaches back
    /// into one that already exists.
    func testDefaultConfigSeedsANewChatAndLeavesAnExistingOneAlone() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let theme = ThemeModel(storing: store)
        let workspace = ChatWorkspace(
            persistentStore: store,
            providers: [MockStreamingProvider.instant],
            mode: .onDeviceOnly,
            temporaryChat: false
        )
        await workspace.start()
        let originalID = try XCTUnwrap(workspace.session?.conversation.id)
        let original = try XCTUnwrap(workspace.session?.conversation.config)
        XCTAssertNotEqual(original.persona, "Only answers in haiku.")

        let edited = ChatConfig(
            persona: "Only answers in haiku.", sampling: SamplingConfig(seed: .fixed(9))
        )
        theme.saveDefaultConfig(edited)
        workspace.apply(defaults: edited)
        XCTAssertEqual(theme.settings.configuredOptionCount, 1, "the badge counts knobs, not persona")

        workspace.startNewChat()
        let fresh = try XCTUnwrap(workspace.session?.conversation.config)
        XCTAssertEqual(fresh, edited)

        XCTAssertEqual(try store.conversation(id: originalID)?.config, original)
    }
}
