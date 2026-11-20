import UIKit
import XCTest
import CairnAppUI

/// Every mark this app draws for a tool row has to be a name UIKit actually resolves.
///
/// An SF Symbol name is a string, so a wrong one compiles, runs, and renders an empty space — no
/// error, no warning, nothing a view test could be asked about. That is exactly how the location row
/// came up as a switch with no mark: it asked for `location.pin`, which does not exist. Asking UIKit
/// whether each name resolves is the only way to catch the next one of these without a person looking
/// at a screen.
final class ToolSymbolTests: XCTestCase {

    func testEveryToolMarkResolvesToAnImage() {
        let names = ToolSwitchLabels.allSymbols
        XCTAssertFalse(names.isEmpty, "a tool type with no marks at all is not what this returns")
        for name in names {
            XCTAssertNotNil(UIImage(systemName: name), "no such SF Symbol: \(name)")
        }
    }

    /// The name that caused the bare row, kept here so it cannot come back as a fresh typo, and so the
    /// test says what the fault was: not an ugly glyph, the absence of one.
    func testTheNameThatDrewNothingIsNeverOfferedAgain() {
        XCTAssertFalse(ToolSwitchLabels.allSymbols.contains("location.pin"))
        XCTAssertNil(UIImage(systemName: "location.pin"), "this name is why the row had no mark")
    }

    /// The marks this app put on screen outside the tool list. They are literals in views, so they are
    /// listed here rather than discovered — which is the honest shape of this assertion: it covers the
    /// names someone wrote down, and nothing that gets written later without being added.
    func testTheMarksUsedAroundTheComposerResolve() {
        for name in [
            "info.circle", "chevron.down.circle.fill", "keyboard.chevron.compact.down",
            "arrow.up", "stop.fill", "paperclip", "checkmark", "wrench"
        ] {
            XCTAssertNotNil(UIImage(systemName: name), "no such SF Symbol: \(name)")
        }
    }
}
