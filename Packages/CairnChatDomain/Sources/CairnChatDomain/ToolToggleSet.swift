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
    /// The switch for `get_location`. On by default like the other local tools, and separate from the
    /// outbound acknowledgement because a position read never leaves the device — the gate on it is
    /// `LocationConsentGate`, which is asked by the tool itself.
    public var getLocation: Bool

    public init(
        isEnabled: Bool = false,
        webSearch: Bool = true,
        webFetch: Bool = true,
        wikiSearch: Bool = true,
        calculator: Bool = true,
        composeMail: Bool = true,
        getLocation: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.webSearch = webSearch
        self.webFetch = webFetch
        self.wikiSearch = wikiSearch
        self.calculator = calculator
        self.composeMail = composeMail
        self.getLocation = getLocation
    }

    public static let `default` = ToolToggleSet()

    /// The chip **up**, with every tool switched on — what one tap on the composer's `Tools` chip means.
    ///
    /// This is a state of its own because `.default` is not it: the shipped default has the chip down, and
    /// a tap that writes the shipped default writes a chip that is still down. That is how the `Tools` chip
    /// came to look dead on a real device — the tap was handled, the write happened, and the chip stayed
    /// unfilled because the value written meant "off".
    public static let armed = ToolToggleSet(isEnabled: true)

    /// Nothing offered, which is what a chat with the chip off resolves to on every turn.
    public static let off = ToolToggleSet(isEnabled: false)

    /// The chip up with the web tools left down: what a user gets when the disclosure is offered and
    /// they choose the on-device half. Arithmetic and mail drafts need no acknowledgement, so the
    /// answer to "no, not the internet" is a working chip, not a refused one.
    public static let localOnly = ToolToggleSet(
        isEnabled: true, webSearch: false, webFetch: false, wikiSearch: false
    )

    public func isOn(_ name: String) -> Bool {
        guard isEnabled else { return false }
        switch name {
        case BuiltInTool.webSearch: return webSearch
        case BuiltInTool.webFetch: return webFetch
        case BuiltInTool.wikiSearch: return wikiSearch
        case BuiltInTool.calculator: return calculator
        case BuiltInTool.composeMail: return composeMail
        case BuiltInTool.getLocation: return getLocation
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
        case BuiltInTool.getLocation: getLocation = on
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
