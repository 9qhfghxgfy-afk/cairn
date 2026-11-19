import Foundation

/// What one tap on the composer's `Tools` chip means.
///
/// The chip used to hold its own answer back. With the outbound acknowledgement down a tap put up a
/// disclosure question instead of arming the chat, so the chip stayed unfilled until the user answered
/// something about a service they may never use — and a phone user who taps once and sees nothing
/// concludes the button is dead. A chip that means "tools" has to answer a tap with tools.
///
/// The question is still asked, because it is a real disclosure: it now travels **with** the chip
/// rather than standing in front of it. The chip goes up on the tap, the web half is withheld by
/// `ToolRouting.offerableNames` until the acknowledgement is granted, and answering "only tools on
/// this device" narrows the switch set rather than undoing the tap.
public enum ToolChipTap: Equatable, Sendable {
    /// The chip was up: the tap takes it down, and no tool vocabulary enters the next prompt.
    case disarm
    /// The chip goes up. `asksAboutWeb` says whether the outbound question is worth putting up
    /// alongside the arming — it never decides whether the chip goes up.
    case arm(asksAboutWeb: Bool)
}

public enum ToolChipRule {
    /// The whole decision, in one call, so the composer has no branch of its own to get wrong.
    ///
    /// Nothing here consults what the backend says it can do: a model that declares no native tool
    /// calling still gets the tools, offered through `PromptToolProtocol`. Capability decides *how* a
    /// call travels (`ToolRouting.format`), never *whether the user may arm the chat*.
    public static func tap(chipIsUp: Bool, outboundWebAllowed: Bool) -> ToolChipTap {
        guard !chipIsUp else { return .disarm }
        return .arm(asksAboutWeb: !outboundWebAllowed)
    }
}
