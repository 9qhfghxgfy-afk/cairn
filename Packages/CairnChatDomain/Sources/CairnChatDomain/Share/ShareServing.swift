import Foundation

/// Whether the surface is up, in the only sense a phone can promise.
public enum ShareRunState: String, Sendable, Equatable, CaseIterable {
    case off
    case starting
    case running
    case failed
    /// Asked to stop, sockets still draining.
    case stopping

    public var isSharing: Bool { self == .running || self == .starting }
}

/// How firmly the operating system pinned the listener to the address this surface asked for.
///
/// **Asking for one address is not the same as getting one.** Whether a listener may be bound to a single
/// interface is the operating system's decision, and it has been observed to refuse: a listener started
/// with a required local endpoint can be rejected outright by the network stack. So the surface records
/// which of the two it actually got, and the screen says it out loud. Letting "bound to your LAN address"
/// be a claim the code does not keep is exactly the kind of promise this app should not make.
///
/// Either way the two policy rules that do the real work are unchanged: the surface refuses to start
/// unless this phone has a **private LAN address**, and every request needs the key.
public enum ShareBindScope: String, Sendable, Equatable, CaseIterable {
    /// Pinned to the address the policy chose: one interface, nothing else.
    case chosenAddress
    /// The system would not pin the port, so it is open on this phone as a whole. The address the user is
    /// told is still the chosen LAN address — it is what a client has to type — but the screen must not
    /// imply the socket is welded to that one interface when it is not.
    case deviceWide
}

/// What the share surface can report right now.
///
/// The bound address is here because the ledger asks for it: a user with a laptop on the same Wi-Fi
/// needs to know what to type. It is **runtime state only** — never written to disk, never included
/// in an export, never logged, because it is an address on the user's own network. Nothing in this
/// repository may contain one.
public struct ShareServerStatus: Sendable, Equatable {
    public var state: ShareRunState
    public var port: Int
    /// Engines this surface is serving right now, in the order the user picked them.
    public var servedModelIDs: [String]
    public var clientCount: Int
    /// The address the listener is bound to, or nil while nothing is bound.
    public var boundAddress: String?
    /// Why the last start or stop failed, as a refusal code — never an address or a key.
    public var failure: ShareRefusal?
    /// True when the surface is serving a turn at this moment.
    public var isServingTurn: Bool
    /// How firmly the port is pinned. Defaults to the weaker of the two, so a status built without
    /// saying anything cannot accidentally claim a guarantee it never got.
    public var bindScope: ShareBindScope

    public init(
        state: ShareRunState = .off,
        port: Int = ShareSettings.defaultPort,
        servedModelIDs: [String] = [],
        clientCount: Int = 0,
        boundAddress: String? = nil,
        failure: ShareRefusal? = nil,
        isServingTurn: Bool = false,
        bindScope: ShareBindScope = .deviceWide
    ) {
        self.state = state
        self.port = port
        self.servedModelIDs = servedModelIDs
        self.clientCount = clientCount
        self.boundAddress = boundAddress
        self.failure = failure
        self.isServingTurn = isServingTurn
        self.bindScope = bindScope
    }

    public static let off = ShareServerStatus()

    public var isSharing: Bool { state.isSharing }
    public var answersRequests: Bool { state == .running }
}

/// The surface the Servers screen drives.
///
/// Declared in the pure domain so `CairnAppUI` can hold it without importing a socket: the real
/// implementation is `CairnShareServer` in `CairnProviderRemote`, and a test implementation is a
/// struct that just remembers what it was asked to do.
@MainActor
public protocol ShareServing: AnyObject {
    var status: ShareServerStatus { get }
    /// Runs the policy, then binds. Returns the refusal, so the screen says which rule stopped it
    /// rather than showing a switch that snapped back with no reason.
    func start(port: Int, token: String, engineIDs: [String]) async -> ShareStartDecision
    func stop() async
}

/// A surface that can also answer "what could I share?", which is a question about the live engine
/// list rather than about the socket.
@MainActor
public protocol ShareEngineListing: AnyObject {
    func availableEngines() -> [ShareModelEntry]
}
