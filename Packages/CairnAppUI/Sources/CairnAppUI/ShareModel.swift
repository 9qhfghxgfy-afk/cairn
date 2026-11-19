import CairnChatDomain
import Foundation
import Observation

/// View model behind the share screen.
///
/// `CairnAppUI` imports neither `Network` nor `Security`, so nothing here opens a socket or touches the
/// Keychain: the surface is the domain's `ShareServing`, the engine list is `ShareEngineListing`, and the
/// key is `ShareTokenStoring`. The App layer injects the real ones out of `CairnProviderRemote`; a
/// simulator test injects doubles. That seam is what lets the switch, the status line, the refusal text
/// and the rotation be proven with no listener and no secure enclave.
@Observable @MainActor
public final class ShareModel {
    public private(set) var status: ShareServerStatus = .off
    /// What could be shared: the live engine list, read when the screen opens.
    public private(set) var offered: [ShareModelEntry] = []
    /// The switch. It is intent, and it is cleared whenever the surface stops — a switch left on over a
    /// closed port would be a claim about reachability that is not true.
    public private(set) var isEnabled = false
    /// The inbound key, as read from the vault. The screen **masks** it; copy hands over the real one.
    public private(set) var token = ""
    public var notice: String?
    /// Port and ticked engines, for this session only. There is no "start sharing at launch" anywhere in
    /// this app: a surface that opens by itself is exactly what this milestone must not do.
    public var settings = ShareSettings.default

    private let serving: any ShareServing
    private let listing: any ShareEngineListing
    private let tokens: any ShareTokenStoring

    public init(
        serving: any ShareServing,
        listing: any ShareEngineListing,
        tokens: any ShareTokenStoring
    ) {
        self.serving = serving
        self.listing = listing
        self.tokens = tokens
    }

    public var statusLine: String { ShareStatusText.statusLine(status) }
    public var addressLine: String? { ShareStatusText.addressLine(status) }
    public var badgeText: String? { ShareStatusText.badge(status) }

    /// The served set is fixed at the moment sharing starts, so the picker and the port go grey while the
    /// port is open — and say why, rather than accepting a tick that changes nothing.
    public var canEditSelection: Bool { !status.isSharing }

    /// The ends of the key with the middle masked: enough to tell two machines they are holding the same
    /// key, not enough to read over a shoulder or to end up legible in a screenshot.
    public var maskedToken: String {
        if token.isEmpty { return "No key yet." }
        guard token.count > 12 else { return String(repeating: "•", count: 12) }
        return "\(token.prefix(4))\(String(repeating: "•", count: 10))\(token.suffix(4))"
    }

    /// Reads the surface, the live engine list and the stored key. **Never generates one**: a key must not
    /// appear in the Keychain just because a screen asked what the key is.
    public func refresh() {
        status = serving.status
        offered = listing.availableEngines()
        token = tokens.token() ?? ""
        isEnabled = status.isSharing
        settings.sharedEngineIDs.removeAll { id in !offered.contains { $0.id == id } }
    }

    /// The switch itself. A refusal is kept as the reason, not swallowed: a switch that snapped back with
    /// nothing on screen is the failure mode this screen exists to avoid.
    public func setSharing(_ on: Bool) async {
        guard on != isEnabled else { return }
        notice = nil
        if !on {
            await serving.stop()
            isEnabled = false
            status = serving.status
            return
        }
        isEnabled = true
        let decision = await serving.start(port: settings.port, token: keyForStart(), engineIDs: settings.sharedEngineIDs)
        isEnabled = decision.isAllowed
        if case .refused(let reason) = decision { notice = ShareStatusText.failureText(reason) }
        status = serving.status
    }

    /// The key the surface starts with: the stored one when it still clears the policy floor, a fresh
    /// generated one otherwise, so a person who never thought about a key still gets a keyed surface.
    private func keyForStart() -> String {
        if let stored = tokens.token(), SharePolicy.tokenIsUsable(stored) { return stored }
        let fresh = tokens.rotate()
        token = fresh
        return fresh
    }

    /// A new key. Every machine configured with the previous one stops working at that moment, which is
    /// the whole point of the button — revocation without uninstalling anything.
    public func regenerateToken() {
        token = tokens.rotate()
        notice = "A new key. Every machine set up with the old one has to be configured again."
    }

    public func toggleEngine(id: String) {
        guard canEditSelection else { return }
        if let index = settings.sharedEngineIDs.firstIndex(of: id) { settings.sharedEngineIDs.remove(at: index) }
        else { settings.sharedEngineIDs.append(id) }
    }

    public func setPort(_ port: Int) {
        guard canEditSelection else { return }
        settings.port = port
    }

    /// Foreground-only. The app calls this the moment the scene leaves the foreground: iOS suspends the
    /// app and takes the listener with it, so the switch is turned off here rather than left glowing over
    /// a port that no longer exists.
    public func releaseToBackground() async {
        guard status.isSharing || isEnabled else { return }
        await serving.stop()
        isEnabled = false
        status = serving.status
        notice = ShareStatusText.backgroundNote
    }
}
