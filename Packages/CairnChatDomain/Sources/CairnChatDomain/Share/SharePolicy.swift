import Foundation

/// Why a share surface may not start, with no address or token in the reason.
public enum ShareRefusal: String, Sendable, Equatable, CaseIterable, Error {
    /// No key at all. The surface is never opened unkeyed.
    case needsToken
    /// A key present but too short to be a key.
    case tokenTooWeak
    /// Nothing selected to serve.
    case needsModel
    /// A port this app may not bind.
    case portUnusable
    /// No private address to bind — the phone is on no network worth binding.
    case noAddress
    /// An address that is not the phone's own network — a public or VPN address.
    case notLocalAddress
    /// One is already running; two listeners on one port is not a second surface.
    case alreadyRunning
}

public enum ShareStartDecision: Sendable, Equatable {
    case allowed
    case refused(ShareRefusal)

    public var isAllowed: Bool { self == .allowed }
}

/// The rules that decide whether the phone may open a port, in one pure place.
///
/// Three of these are privacy rules, not preferences:
/// - **a key is required.** A LAN is the user's own network, but it is not an empty one: a café
///   Wi-Fi, a landlord's router and a neighbour's laptop are all "local". An unkeyed model server
///   on a phone is an open spend of the phone's battery and of any server behind it.
/// - **the bind is LAN-only.** Binding a wildcard means "every interface, including whichever one
///   the carrier gave this phone". Binding one private address means exactly one interface.
/// - **a public or VPN address is refused.** This surface is defined as the local link; the away
///   case is served by the phone dialing out, not by the phone listening.
public enum SharePolicy {
    /// Shortest accepted key. Below this, a "token" is a word, not a key.
    public static let tokenCharacterFloor = 16
    public static let portFloor = 1024
    public static let portCeiling = 65_535

    public static func tokenIsUsable(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= tokenCharacterFloor && !trimmed.contains(" ")
    }

    public static func portIsUsable(_ port: Int) -> Bool {
        (portFloor...portCeiling).contains(port)
    }

    /// Only the phone's own local link: loopback, RFC 1918, `.local`, or an unqualified name.
    ///
    /// An empty string is refused here as well as in `decide`, because the classifier reads "no
    /// host at all" as an unqualified name and therefore as the local link — which would let a
    /// caller who never looked up an address through a rule whose whole job is "an address on the
    /// phone's own link".
    public static func addressIsBindable(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return NetworkClassRouting.classify(host: trimmed) == .privateLan
    }

    public static func isLoopback(_ address: String) -> Bool {
        address == "localhost" || address.hasPrefix("127.") || address == "::1"
    }

    /// Ordered so the first refusal is the one the user can act on first.
    public static func decide(
        running: Bool,
        token: String?,
        address: String?,
        port: Int,
        sharedEngineCount: Int
    ) -> ShareStartDecision {
        if running { return .refused(.alreadyRunning) }
        guard let token, !token.isEmpty else { return .refused(.needsToken) }
        guard tokenIsUsable(token) else { return .refused(.tokenTooWeak) }
        guard sharedEngineCount > 0 else { return .refused(.needsModel) }
        guard portIsUsable(port) else { return .refused(.portUnusable) }
        guard let address, !address.isEmpty else { return .refused(.noAddress) }
        guard addressIsBindable(address) else { return .refused(.notLocalAddress) }
        return .allowed
    }
}
