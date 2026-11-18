import XCTest
@testable import CairnChatDomain

/// The names a mode is shown by. Small, and worth pinning: the same four words appear on the chat's mode
/// switcher and in the list of chats, and the day the two disagree is the day a user is told the chat is
/// doing something the switch does not say.
final class InferenceModeLabelTests: XCTestCase {
    func testEveryModeIsNamedInWordsAUserCanRead() {
        XCTAssertEqual(InferenceMode.onDeviceOnly.displayName, "On device")
        XCTAssertEqual(InferenceMode.remoteOnly.displayName, "Remote")
        XCTAssertEqual(InferenceMode.hybridParallel.displayName, "Hybrid parallel")
        XCTAssertEqual(InferenceMode.hybridSynthesized.displayName, "Hybrid synthesized")
    }

    func testNoModeIsNamedWithItsOwnCaseName() {
        for mode in InferenceMode.allCases {
            XCTAssertFalse(
                mode.displayName.contains(mode.rawValue),
                "\(mode.rawValue) is the code's name, not the user's"
            )
            XCTAssertFalse(mode.displayName.isEmpty)
        }
    }
}
