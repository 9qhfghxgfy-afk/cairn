import Foundation

/// Which tools a chat may use, and whether it may use any at all.
///
/// Two levels, because they are two different decisions. `isEnabled` is the composer's `Tools` chip:
/// with it off no tool is named anywhere in the prompt and nothing can be called, which is the state
/// the app ships in. The per-tool switches say *which* tools the chip means when it is on — a user
/// who wants arithmetic but not a search query leaving the phone can have exactly that.
///
/// The chip defaults to off and the tools default to on: off, because a tool that reaches the network
/// should never be live in a chat the user did not arm; on, because once the chip is up, a set with
/// five switches the user has to flip is a trap.
public struct ToolToggleSet: Sendable, Equatable, Codable {
    /// The composer chip. Off means no tool vocabulary enters the prompt at all.
    public var isEnabled: Bool
    public var webSearch: Bool
    public var webFetch: Bool
    public var wikiSearch: Bool
    public var calculator: Bool
    public var composeMail: Bool

    public init(
        isEnabled: Bool = false,
        webSearch: Bool = true,
        webFetch: Bool = true,
        wikiSearch: Bool = true,
        calculator: Bool = true,
        composeMail: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.webSearch = webSearch
        self.webFetch = webFetch
        self.wikiSearch = wikiSearch
        self.calculator = calculator
        self.composeMail = composeMail
    }

    public static let `default` = ToolToggleSet()

    /// Nothing offered, which is what a chat with the chip off resolves to on every turn.
    public static let off = ToolToggleSet(isEnabled: false)

    public func isOn(_ name: String) -> Bool {
        guard isEnabled else { return false }
        switch name {
        case BuiltInTool.webSearch: return webSearch
        case BuiltInTool.webFetch: return webFetch
        case BuiltInTool.wikiSearch: return wikiSearch
        case BuiltInTool.calculator: return calculator
        case BuiltInTool.composeMail: return composeMail
        // An unknown tool cannot be switched on from this set, and a tool the user has never seen a
        // switch for is not something to offer silently.
        default: return false
        }
    }

    public mutating func setOn(_ name: String, _ on: Bool) {
        switch name {
        case BuiltInTool.webSearch: webSearch = on
        case BuiltInTool.webFetch: webFetch = on
        case BuiltInTool.wikiSearch: wikiSearch = on
        case BuiltInTool.calculator: calculator = on
        case BuiltInTool.composeMail: composeMail = on
        default: break
        }
    }

    /// The names this set would offer, in the fixed `BuiltInTool` order so the list a model sees is
    /// the same list every turn.
    public var enabledToolNames: [String] {
        guard isEnabled else { return [] }
        return BuiltInTool.allNames.filter { isOn($0) }
    }

    public var enabledCount: Int { enabledToolNames.count }

    /// True when this set contains something that sends data to a public service — the condition the
    /// outbound badge and its warning exist for.
    public var includesWebTools: Bool {
        guard isEnabled else { return false }
        return webSearch || webFetch || wikiSearch
    }
}
