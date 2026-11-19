import CairnChatDomain

/// What each tool switch is called, and the mark drawn beside it.
///
/// Split out of the menu so the mapping can be checked rather than looked at. A symbol name that does not
/// exist does not fail a build and does not crash — it draws nothing, and a switch appears with no mark at
/// all, which is how a calculator row once showed an empty space. A test can ask `UIImage(systemName:)`
/// whether a name resolves; it cannot ask a view what it looked like.
public enum ToolSwitchLabels {
    public static func title(_ name: String) -> String {
        switch name {
        case BuiltInTool.webSearch: return "Web search"
        case BuiltInTool.webFetch: return "Read a page"
        case BuiltInTool.wikiSearch: return "Wikipedia"
        case BuiltInTool.calculator: return "Calculator"
        case BuiltInTool.composeMail: return "Draft an email"
        case BuiltInTool.getLocation: return "My location"
        default: return name
        }
    }

    public static func symbol(_ name: String) -> String {
        switch name {
        case BuiltInTool.webSearch: return "magnifyingglass"
        case BuiltInTool.webFetch: return "doc.plaintext"
        case BuiltInTool.wikiSearch: return "book"
        // Not `plus.minus`, which is not a symbol and draws an empty space. The calculator mark is a plus
        // with a minus after it.
        case BuiltInTool.calculator: return "plus.forwardslash.minus"
        case BuiltInTool.composeMail: return "envelope"
        case BuiltInTool.getLocation: return "location.pin"
        default: return "wrench"
        }
    }
}
