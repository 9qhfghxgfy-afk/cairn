import XCTest
@testable import CairnChatDomain

/// What each mode says about itself, next to the switch that chooses it.
///
/// A mode chosen from a four-word label is a mode chosen by guesswork, and two of Cairn's four modes
/// send a prompt to another machine while one of them merges two answers into one node. So every mode
/// owes a plain-language note, and the note has to keep three promises: what runs, what leaves the
/// device, and when to pick it. A test can check the promises; it cannot check that the wording is
/// pleasant, so it does not try.
final class InferenceModeExplainerTests: XCTestCase {
    func testEveryModeExplainsItselfInMoreThanAName() {
        for mode in InferenceMode.allCases {
            XCTAssertFalse(mode.explainer.isEmpty)
            XCTAssertGreaterThan(
                mode.explainer.count,
                120,
                "\(mode) is described in a phrase, not in sentences"
            )
            XCTAssertNotEqual(mode.explainer, mode.displayName)
            // The code's name never reaches the screen: "hybridSynthesized" is not a word a user reads.
            XCTAssertFalse(
                mode.explainer.contains(mode.rawValue),
                "\(mode.rawValue) is the code's name, not the user's"
            )
        }
    }

    /// The privacy promise, per mode. Two modes are on-device and must not imply a server; two reach
    /// one, and saying so is the whole point of the outbound badge.
    func testEachModeSaysWhetherThePromptLeavesThePhone() {
        XCTAssertTrue(InferenceMode.onDeviceOnly.explainer.lowercased().contains("nothing"))
        XCTAssertTrue(InferenceMode.onDeviceOnly.explainer.lowercased().contains("no network"))
        XCTAssertTrue(InferenceMode.remoteOnly.explainer.lowercased().contains("leaves"))
        XCTAssertTrue(InferenceMode.hybridParallel.explainer.lowercased().contains("both"))
        XCTAssertTrue(InferenceMode.hybridSynthesized.explainer.lowercased().contains("draft"))
    }

    func testTheOnDeviceNoteStatesTheWindowItActuallyHas() {
        // The number the provider declares and the number the note promises have to be the same
        // number, or the note is a claim about a limit the engine does not have.
        XCTAssertTrue(InferenceMode.onDeviceOnly.explainer.contains("4,096"))
    }

    func testTheTitleIsTheModesOwnName() {
        for mode in InferenceMode.allCases {
            XCTAssertEqual(mode.explainerTitle, mode.displayName)
        }
    }
}
