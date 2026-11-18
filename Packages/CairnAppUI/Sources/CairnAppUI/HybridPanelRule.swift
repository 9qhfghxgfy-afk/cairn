import Foundation
import CairnChatDomain

/// When the chat header shows the live hybrid panel instead of the single-stream status line.
///
/// Three conditions, and the mode is one of them on purpose: a session keeps its last hybrid snapshot
/// standing after the turn ends so the panels can still be read, so "a snapshot exists" alone would
/// make a finished hybrid turn animate forever in the header of a chat that has since moved on to a
/// plain turn. Once the turn is over, the drafts stored on the node are what the user reads.
enum HybridPanelRule {
    static func showsPanel(mode: InferenceMode, isBusy: Bool, hasSnapshot: Bool) -> Bool {
        mode.isHybrid && isBusy && hasSnapshot
    }
}
