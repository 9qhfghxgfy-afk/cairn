import Foundation

/// When the `Force Web Fetch` block is allowed to describe a turn.
///
/// `ContextAssembly.isLive` already refuses to write a conditional block whose feature is not running;
/// this is the side that decides whether that feature *is* running, and it used to be hardcoded `false`
/// — which left the toggle in the sheet with nothing to switch on.
extension ContextAssembly {
    /// True when the user switched `Force Web Fetch` on **and** this turn really is being offered a web
    /// tool.
    ///
    /// The block says "a web search ran for this turn", so a turn armed only for the calculator must not
    /// carry it: a toggle that is on describes nothing on a turn where the feature is not running, and a
    /// model told to cite a page it was never offered a way to read invents one. `ToolRouting` has
    /// already removed a web tool that the outbound acknowledgement has not released, so "offered" here
    /// means the model can actually run it.
    public static func webFetchIsLive(toggles: ContextToggleSet, offered: ToolSelection) -> Bool {
        guard toggles.forceWebFetch, !offered.isEmpty else { return false }
        return offered.definitions.contains {
            $0.name == BuiltInTool.webFetch || $0.name == BuiltInTool.webSearch
        }
    }
}
