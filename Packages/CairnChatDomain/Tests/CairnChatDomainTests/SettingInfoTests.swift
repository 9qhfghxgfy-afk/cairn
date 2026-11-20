import XCTest
@testable import CairnChatDomain

/// Every `(i)` card the app can open, checked as data rather than as pixels.
///
/// A popover is only worth having if it says something. The promises pinned here are the ones a view cannot
/// make from the inside: that every named control has copy, that the copy is sentences rather than the name
/// repeated, that no case leaks the code's spelling onto the screen, and that every surface with a changeable
/// control is covered — because a screen with nine `(i)` buttons and one missing teaches people that the
/// button is decoration.
final class SettingInfoTests: XCTestCase {
    /// Shortest detail accepted. Anything under this is a phrase, and a phrase next to a control the user is
    /// already reading is not an explanation.
    private let minimumDetailLength = 160

    func testEveryKeyCarriesBothStrings() {
        for key in SettingInfoKey.allCases {
            XCTAssertFalse(key.info.title.isEmpty, "\(key) has no title")
            XCTAssertFalse(key.info.detail.isEmpty, "\(key) has no detail")
            XCTAssertNotEqual(
                key.info.detail, key.info.title,
                "\(key) explains itself by repeating its own name"
            )
            XCTAssertGreaterThan(
                key.info.detail.count, minimumDetailLength,
                "\(key) is described in a phrase, not in sentences"
            )
            // A camelCase raw value is a code spelling and must never reach the screen; a single-word one
            // ("date", "seed", "appearance") is English the user reads anyway, so only the first is a leak.
            if key.rawValue.rangeOfCharacter(from: .uppercaseLetters) != nil {
                XCTAssertFalse(
                    key.info.title.contains(key.rawValue) || key.info.detail.contains(key.rawValue),
                    "\(key.rawValue) is the code's name, not the user's"
                )
            }
            XCTAssertEqual(
                key.info.detail,
                key.info.detail.trimmingCharacters(in: .whitespacesAndNewlines),
                "\(key) has stray whitespace at either end of the card"
            )
        }
    }

    func testEveryKeyBelongsToAKnownSurface() {
        for key in SettingInfoKey.allCases {
            XCTAssertTrue(SettingInfoGroup.allCases.contains(key.group), "\(key) belongs to no surface")
        }
    }

    /// Every surface that has a changeable control has to be covered, and the number per surface is the audit
    /// itself: a suite that only proves "some entry exists" passes while a whole screen stays unlabelled.
    func testEverySurfaceIsCovered() {
        let expected: [SettingInfoGroup: Int] = [
            .settings: 8, .chat: 5, .webSearch: 11, .server: 7, .sharing: 4,
        ]
        for group in SettingInfoGroup.allCases {
            let found = SettingInfoKey.allCases.filter { $0.group == group }
            XCTAssertFalse(found.isEmpty, "\(group) has no info entry at all")
            XCTAssertEqual(
                found.count, expected[group],
                "\(group) does not have the expected number of entries"
            )
        }
        XCTAssertEqual(SettingInfoKey.allCases.count, 35)
    }

    /// The controls the audit names by hand, so a rename that silently drops one out of the catalog fails
    /// here rather than turning one row back into a control with no explanation.
    func testTheNamedControlsAreAllPresent() {
        let required: [SettingInfoKey] = [
            .appearance, .colorTheme, .defaultConfiguration, .injectedContext, .generationStats,
            .webToolsOutbound, .persona, .answerStyle, .askForReasoning, .toolSwitches, .temporaryChat,
            .webSearchProvider, .webSearchResultCount, .webSearchInstanceName, .webSearchAddress,
            .webSearchCategories, .webSearchLanguage, .webSearchSafeSearch, .webSearchTimeRange,
            .webSearchTimeout, .webSearchCredential, .webSearchCustomHeaders,
            .serverName, .serverBackend, .serverAddress, .serverUseEnabled, .serverPublicOptIn,
            .serverToken, .serverCustomHeaders,
            .shareOnLocalNetwork, .sharePeerKey, .sharePort, .shareEngines,
        ]
        for key in required {
            XCTAssertTrue(SettingInfoKey.allCases.contains(key), "\(key) is missing from the catalog")
        }
    }

    /// The claims that have to survive in the copy, because a card that leaves one out describes the opposite
    /// of what the control does.
    func testCopyMakesThePromiseEachControlOwes() {
        XCTAssertTrue(SettingInfoKey.appearance.info.detail.contains("System"))
        XCTAssertTrue(SettingInfoKey.defaultConfiguration.info.detail.lowercased().contains("new chat"))
        XCTAssertTrue(SettingInfoKey.injectedContext.info.detail.lowercased().contains("ahead"))
        XCTAssertTrue(SettingInfoKey.generationStats.info.detail.lowercased().contains("tokens per second"))
        XCTAssertTrue(SettingInfoKey.webToolsOutbound.info.detail.lowercased().contains("badge"))
        XCTAssertTrue(SettingInfoKey.webSearchProvider.info.detail.lowercased().contains("never"))
        XCTAssertTrue(SettingInfoKey.webSearchCredential.info.detail.contains("Keychain"))
        XCTAssertTrue(SettingInfoKey.webSearchCustomHeaders.info.detail.contains("X-API-Key"))
        XCTAssertTrue(SettingInfoKey.webSearchResultCount.info.detail.contains("3 and 10"))
        XCTAssertTrue(SettingInfoKey.serverToken.info.detail.contains("Keychain"))
        XCTAssertTrue(SettingInfoKey.serverAddress.info.detail.lowercased().contains("https"))
        XCTAssertTrue(SettingInfoKey.shareOnLocalNetwork.info.detail.lowercased().contains("foreground"))
        XCTAssertTrue(SettingInfoKey.sharePeerKey.info.detail.lowercased().contains("key"))
        XCTAssertTrue(SettingInfoKey.toolSwitches.info.detail.lowercased().contains("badge"))
        XCTAssertTrue(SettingInfoKey.temporaryChat.info.detail.lowercased().contains("disk"))
        XCTAssertTrue(SettingInfoKey.webSearchSafeSearch.info.detail.lowercased().contains("explicit"))
        XCTAssertTrue(SettingInfoKey.webSearchTimeRange.info.detail.lowercased().contains("recency"))
        XCTAssertTrue(SettingInfoKey.serverUseEnabled.info.detail.lowercased().contains("server"))
    }
}
