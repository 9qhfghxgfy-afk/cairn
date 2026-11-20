import XCTest
@testable import CairnChatDomain

/// The copy that lives beside the wire keys — `SamplingKey.explainer` and `ContextKey.explainer` — under the
/// same rule the settings catalog is held to.
///
/// These two enums already carry their explanations next to the encoding they describe, which is the right
/// home for them. What they did not have was a test: an explainer could go empty, or shrink to a clause, and
/// the sheet would still build and still show a button.
final class KnobExplainerTests: XCTestCase {
    func testEverySamplingKnobExplainsItself() {
        for key in SamplingKey.allCases {
            XCTAssertFalse(key.explainer.isEmpty, "\(key) has no explainer")
            XCTAssertNotEqual(key.explainer, key.displayName, "\(key) repeats its own name")
            if Self.isCodeSpelling(key.rawValue) {
                XCTAssertFalse(key.explainer.contains(key.rawValue), "\(key.rawValue) is not a user's word")
            }
            XCTAssertGreaterThan(key.explainer.count, 120, "\(key) is a phrase, not an explanation")
        }
    }

    /// The numbers a person can act on. "Lower is tighter" beside a slider with no range on it is a mood, not
    /// guidance, and every knob here is a range the user can move.
    func testTheKnobsSayWhichEndIsWhich() {
        XCTAssertTrue(SamplingKey.temperature.explainer.contains("0.3"))
        XCTAssertTrue(SamplingKey.temperature.explainer.contains("0.8"))
        XCTAssertTrue(SamplingKey.topP.explainer.contains("1.00"))
        XCTAssertTrue(SamplingKey.minP.explainer.lowercased().contains("top choice"))
        XCTAssertTrue(SamplingKey.topK.explainer.lowercased().contains("k most likely"))
        XCTAssertTrue(SamplingKey.seed.explainer.contains("Random"))
        XCTAssertTrue(SamplingKey.seed.explainer.contains("Fixed"))
        XCTAssertTrue(SamplingKey.contextWindow.explainer.lowercased().contains("memory"))
        XCTAssertTrue(SamplingKey.repeatPenalty.explainer.contains("1.00"))
        XCTAssertTrue(SamplingKey.repeatLastN.explainer.lowercased().contains("looks back"))
        XCTAssertTrue(SamplingKey.maxTokens.explainer.lowercased().contains("unlimited"))
    }

    /// Every knob is a set/unset decision first, so every card has to say what unset does — otherwise the
    /// switch reading "off" and the server's own value both look like the same thing.
    func testEverySettableKnobSaysWhatUnsetMeans() {
        for key in SamplingKey.allCases where key != .maxTokens {
            XCTAssertTrue(
                key.explainer.lowercased().contains("unset"),
                "\(key) can be unset and its card does not say what that means"
            )
        }
        XCTAssertTrue(SamplingKey.maxTokens.explainer.lowercased().contains("no limit"))
    }

    func testEveryContextToggleExplainsItself() {
        for key in ContextKey.allCases {
            XCTAssertFalse(key.explainer.isEmpty, "\(key) has no explainer")
            XCTAssertNotEqual(key.explainer, key.displayName, "\(key) repeats its own name")
            if Self.isCodeSpelling(key.rawValue) {
                XCTAssertFalse(key.explainer.contains(key.rawValue), "\(key.rawValue) is not a user's word")
            }
            XCTAssertGreaterThan(key.explainer.count, 100, "\(key) is a phrase, not an explanation")
        }
    }

    /// A camelCase raw value ("timeAndTimezone") is a code spelling that must never reach the screen. A
    /// single-word one ("date", "seed") is the English the user reads anyway, so it is not a leak.
    private static func isCodeSpelling(_ raw: String) -> Bool {
        raw.rangeOfCharacter(from: .uppercaseLetters) != nil
    }

    /// The four conditional blocks have to say they are conditional, or a switch reading "on" is a false
    /// statement about a turn that sends nothing.
    func testTheConditionalBlocksSayWhenTheyAreAdded() {
        for key in ContextToggleSet.conditionalKeys {
            XCTAssertTrue(
                key.explainer.lowercased().contains("only"),
                "\(key) is conditional and its card does not say so"
            )
        }
    }

    /// A live clock is a caveat as well as a fact: the smaller the model, the likelier it is to answer about
    /// the timestamp instead of using it. Said once here so no view has to restate it and get it wrong.
    func testTheTimeTogglesCarryTheirCaveat() {
        XCTAssertTrue(ContextKey.date.explainer.lowercased().contains("small model"))
        XCTAssertTrue(ContextKey.timeAndTimezone.explainer.lowercased().contains("small model"))
        XCTAssertTrue(ContextKey.timeAndTimezone.explainer.lowercased().contains("identifying"))
    }
}
