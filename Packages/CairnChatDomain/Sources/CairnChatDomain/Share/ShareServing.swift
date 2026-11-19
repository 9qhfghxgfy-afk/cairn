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

    public init(
        state: ShareRunState = .off,
        port: Int = ShareSettings.defaultPort,
        servedModelIDs: [String] = [],
        clientCount: Int = 0,
        boundAddress: String? = nil,
        failure: ShareRefusal? = nil,
        isServingTurn: Bool = false
    ) {
        self.state = state
        self.port = port
        self.servedModelIDs = servedModelIDs
        self.clientCount = clientCount
        self.boundAddress = boundAddress
        self.failure = failure
        self.isServingTurn = isServingTurn
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
