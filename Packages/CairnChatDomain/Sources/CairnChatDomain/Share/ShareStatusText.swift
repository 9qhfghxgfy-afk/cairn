import Foundation

/// Every word the share surface says, in one pure file so the claims are reviewable and testable.
///
/// Two of these are the **documented limits** the milestone owes. A phone is not a server: iOS
/// suspends an app that is not in the foreground, and a suspended app has no running listener.
/// Saying that plainly is part of shipping the feature — the alternative is a user whose laptop
/// stops reaching the phone an hour later with nothing on screen that explains it. There is no
/// background mode for this, and a free Apple ID cannot add one, so the limit is stated, not
/// worked around.
public enum ShareStatusText {
    public static let title = "Share over the local network"

    /// The persistent badge. It stays up the whole time a port is open, which is the rule every
    /// outbound and inbound surface in this app follows.
    public static func badge(_ status: ShareServerStatus) -> String? {
        guard status.isSharing else { return nil }
        return status.state == .starting ? "Opening" : "Sharing"
    }

    public static func statusLine(_ status: ShareServerStatus) -> String {
        switch status.state {
        case .off: return "Off. Nothing on this phone is reachable from another machine."
        case .starting: return "Opening a port on your local network..."
        case .running:
            var parts = ["Port \(status.port)", "\(status.clientCount) client\(status.clientCount == 1 ? "" : "s") connected"]
            parts.append("\(status.servedModelIDs.count) model\(status.servedModelIDs.count == 1 ? "" : "s") shared")
            if status.isServingTurn { parts.append("answering now") }
            // Only the weaker case is called out: a pinned port needs no caveat, a device-wide one does.
            if status.bindScope == .deviceWide { parts.append("open on every interface") }
            return parts.joined(separator: " · ")
        case .stopping: return "Closing the port..."
        case .failed: return "Could not open the port. \(failureText(status.failure))"
        }
    }

    /// How firmly the port is pinned, said plainly — and only while something is bound.
    ///
    /// This is the sentence that keeps the address line honest. The address is what a client types either
    /// way; whether the operating system welded the socket to that one interface is a separate fact, and
    /// a screen that printed only the address would be claiming more than the system granted.
    public static func bindNote(_ status: ShareServerStatus) -> String? {
        guard status.isSharing else { return nil }
        switch status.bindScope {
        case .chosenAddress:
            return "The port is bound to that address only — one interface on this phone."
        case .deviceWide:
            return "This system would not pin the port to a single address, so it is open on this phone as a whole. The address above is still what a client types, and the key is still what decides who gets answered."
        }
    }

    /// What to type on the other machine. Only ever shown on this phone, at runtime: the address is
    /// the phone's own address on the user's own network, and it never leaves the screen.
    public static func addressLine(_ status: ShareServerStatus) -> String? {
        guard status.state == .running, let address = status.boundAddress else { return nil }
        return "On this phone: \(address):\(status.port)"
    }

    public static func failureText(_ refusal: ShareRefusal?) -> String {
        switch refusal {
        case .none: return "The port could not be bound."
        case .needsToken: return "A key is required before a port can be opened."
        case .tokenTooWeak: return "That key is too short to be a key — generate one, or type at least 16 characters."
        case .needsModel: return "Nothing is ticked to share."
        case .portUnusable: return "That port cannot be used. Pick one between 1024 and 65535."
        case .noAddress: return "This phone is not on a local network to bind. Join your Wi-Fi first."
        case .notLocalAddress: return "Only your own local network can be bound — never a public address."
        case .alreadyRunning: return "It is already running."
        }
    }

    /// Why a key is not optional here.
    public static let tokenNote = "Every request needs this key, including the model list. A local network is your network, not an empty one."

    /// The suspension limit, stated as what the user will observe.
    public static let suspensionNote = "A phone is not a server. iOS suspends Cairn minutes after it leaves the foreground, and the port closes with it — sharing lasts while Cairn is open on screen, not after."

    /// The permission that really breaks this, not cosmetically.
    public static let permissionNote = "The first connection from another machine needs the Local Network permission. If it was denied, clients cannot reach this phone at all."

    /// What the app says when it closes the port because it left the foreground — which is the same
    /// limit as the suspension note, told at the moment the user will otherwise assume it broke.
    public static let backgroundNote = "Cairn left the foreground, so the port is closed and the switch is off. A phone that kept listening while suspended would be reachable with nothing on screen to say so."

    /// The empty picker's own sentence: sharing offers engines this app can actually run, so with nothing
    /// loaded on the phone and nothing installed on a server there is genuinely nothing to offer — and an
    /// empty shared list is not a safe port, it is the same port with nothing to show.
    public static let noEnginesNote = "Nothing to share yet. An engine has to be running on this phone, or installed on a server you added, before it can appear here."

    /// What is served, and what that means for the engine behind it.
    public static func servingNote(_ status: ShareServerStatus) -> String {
        guard status.isSharing else {
            return "Nothing is shared until you tick at least one engine and open the port. Off is the default, and it starts off every time the app launches."
        }
        return "Serving the engines ticked below, keyed by the token above. If a shared engine is a server elsewhere, a client reaching this phone reaches that server too."
    }

    public static let pathsNote = "Answers Ollama's /api/version, /api/tags, /api/chat, /api/generate and the OpenAI-compatible /v1/models, /v1/chat/completions, /v1/completions — plain HTTP, on your LAN only."
}
