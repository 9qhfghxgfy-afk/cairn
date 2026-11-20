import Foundation

/// The copy for the local-sharing screen.
///
/// This is the one surface where this phone accepts traffic from another machine, so the two facts a person
/// has to be told are the one that ends (the port closes when Cairn leaves the foreground) and the one that
/// decides who gets answered (the key). Both are said on the screen already, in `ShareStatusText`; these cards
/// say why.
extension SettingInfoKey {
    static var shareOnLocalNetworkInfo: SettingInfo {
        SettingInfo(
            title: "Share on Local Network",
            detail: """
            Opens a port on this phone so another machine on your own network or VPN can send requests to the \
            on-device model loaded here, authenticated with the peer key below. A phone is not a server: iOS \
            suspends Cairn minutes after it leaves the foreground and the port closes with it, so sharing \
            lasts while Cairn is on screen and not after. The first connection from another machine also needs \
            iOS's own Local Network permission, and if that was denied, clients cannot reach this phone at all.
            """
        )
    }

    static var sharePeerKeyInfo: SettingInfo {
        SettingInfo(
            title: "Peer Key",
            detail: """
            The key every request has to present, including a model list. It is generated rather than typed, \
            shown masked so it stays unreadable over a shoulder or in a screenshot, and rotated by the button \
            below — rotation takes effect at once and breaks any client still holding the old key. Copy hands \
            over the real value, because a laptop cannot authenticate with a masked one.
            """
        )
    }

    static var sharePortInfo: SettingInfo {
        SettingInfo(
            title: "Port",
            detail: """
            The port the shared surface binds to. Ollama's usual port is 11434, and anything 1024 or above \
            that nothing else is using will do — a number below 1024 is a system port and is not offered. A \
            port that cannot be bound is reported with the reason rather than quietly tried somewhere else, \
            and only an address on your own network is ever bound.
            """
        )
    }

    static var shareEnginesInfo: SettingInfo {
        SettingInfo(
            title: "What Is Shared",
            detail: """
            Which engines a peer may call, and under which names. Only what is ticked here is served, a name \
            with no engine behind it is refused rather than invented, and the set is fixed when the port opens \
            so it cannot shift under a client that is already talking to this phone. If a shared engine is \
            itself a server elsewhere, a client reaching this phone reaches that server too.
            """
        )
    }
}
