import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Putting text on the device's pasteboard, in the one place that touches it.
///
/// Copy is a local act: nothing leaves the phone and nothing is written down. The guard scripts are about
/// logging, and this is not logging — the user asked for exactly this text, and it goes to the pasteboard
/// and nowhere else.
///
/// Main-actor isolated because that is where UIKit's pasteboard lives, and because every caller is a view.
/// Marking it says so rather than letting an off-main caller slip in a pasteboard write that UIKit would
/// not have allowed.
@MainActor
enum Pasteboard {
    /// Copies the text and reports whether it landed, so a view only says "Copied" when it is true.
    @discardableResult
    static func copy(_ text: String) -> Bool {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        return true
        #else
        return false
        #endif
    }
}
