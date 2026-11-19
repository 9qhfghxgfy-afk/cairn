import CairnChatDomain
import Foundation

/// The share surface itself: the policy goes in, sockets come out, and one status object is what the
/// screen reads.
///
/// Three things this type is responsible for and cannot delegate:
/// - **the policy runs before anything is bound.** A refusal is returned as a code, so the screen can
///   say which rule stopped the switch instead of showing a switch that snapped back on its own.
/// - **the served set is fixed at start.** Turning sharing on is the opt-in; a profile saved
///   afterwards does not join a surface that is already open, because quietly serving a new engine to
///   the local network is an outbound path nobody switched on.
/// - **sharing is foreground-only.** A phone that keeps listening after it is backgrounded is a
///   phone whose owner cannot see that it is reachable. The app wiring calls `stop()` when the scene
///   leaves the foreground; nothing here tries to stay alive behind its back.
@MainActor
public final class CairnShareServer: ShareServing, ShareEngineListing {
    public private(set) var status: ShareServerStatus = .off

    let transport: ShareSocketTransport
    /// The live engine list, read at the moment sharing starts.
    ///
    /// A **main-actor closure rather than a `@Sendable` one**, because that is what the app can
    /// actually hand over: the live list lives in a `ProviderRegistry`, a main-actor-owned object and
    /// not a `Sendable` value, so a `@Sendable` closure could not capture it. Every read here happens
    /// on the main actor anyway — `start` and `availableEngines` are both main-actor methods — and
    /// what crosses to a socket is a `Sendable` `ShareEngineTable` snapshot, never this closure.
    private let engineSource: @MainActor () -> [any InferenceProvider]
    private let addressSource: @MainActor () -> String?
    var table = ShareEngineTable()
    var token = ""
    var turnTasks: [Task<Void, Never>] = []
    var openClients = 0

    public init(
        engines: @escaping @MainActor () -> [any InferenceProvider],
        addressSource: @escaping @MainActor () -> String?
    ) {
        self.transport = ShareSocketTransport()
        self.engineSource = engines
        self.addressSource = addressSource
        transport.onConnection = { [weak self] socket in
            Task { @MainActor in self?.accept(socket) }
        }
    }

    /// Sharing with no address chosen by the caller: the phone's own private address, read from the
    /// interface table.
    ///
    /// It has to be spelled in an initializer body rather than as a default argument, because
    /// `LocalIPv4Reader` is module-internal and a public default argument may not name an internal
    /// type — the compiler rejects it, which is the right rule: a public signature cannot quietly
    /// promise a dependency the module does not export.
    public convenience init(engines: @escaping @MainActor () -> [any InferenceProvider]) {
        self.init(engines: engines, addressSource: { LocalIPv4Reader.primaryAddress() })
    }

    public func availableEngines() -> [ShareModelEntry] {
        engineSource().map { ShareModelEntry(id: $0.id, displayName: $0.displayName, engineID: $0.id) }
    }

    public func start(port: Int, token: String, engineIDs: [String]) async -> ShareStartDecision {
        let built = ShareEngineTable.build(from: engineSource(), selected: engineIDs)
        let decision = SharePolicy.decide(
            running: status.isSharing,
            token: token,
            address: addressSource(),
            port: port,
            sharedEngineCount: built.entries.count
        )
        guard case .allowed = decision else {
            status = ShareServerStatus(state: .failed, port: port, servedModelIDs: built.servedIDs, failure: refusal(in: decision))
            return decision
        }
        guard let address = addressSource() else {
            status = ShareServerStatus(state: .failed, port: port, servedModelIDs: built.servedIDs, failure: .noAddress)
            return .refused(.noAddress)
        }

        status = ShareServerStatus(state: .starting, port: port, servedModelIDs: built.servedIDs)
        // The scope is what the system actually granted, not what was asked for: a port pinned to the
        // chosen address and a port bound device-wide are different facts, and the screen says which.
        guard let scope = await transport.start(address: address, port: port) else {
            // The bind failed. Which system error it was is not reportable here — a failure string can
            // carry an address — so the screen gets the code that describes a port that will not open.
            status = ShareServerStatus(state: .failed, port: port, servedModelIDs: built.servedIDs, failure: .portUnusable)
            return .refused(.portUnusable)
        }

        self.table = built
        self.token = token
        status = ShareServerStatus(
            state: .running,
            port: port,
            servedModelIDs: built.servedIDs,
            boundAddress: address,
            bindScope: scope
        )
        return .allowed
    }

    public func stop() async {
        guard status.state != .off else { return }
        status.state = .stopping
        for task in turnTasks { task.cancel() }
        turnTasks.removeAll()
        transport.stop()
        table = ShareEngineTable()
        token = ""
        openClients = 0
        status = .off
    }

    /// Client and turn counters. Kept as methods on the class so the socket file only ever reports
    /// events and never edits status from off the main actor.
    func noteClient(opened: Bool) {
        openClients = max(0, openClients + (opened ? 1 : -1))
        status.clientCount = openClients
        // Once no client is connected, every task that was running one has finished, so the list is
        // dropped rather than tracked per request — which is also what keeps it from growing forever.
        if openClients == 0 { turnTasks.removeAll() }
    }

    /// Whether a turn is being answered right now — the one thing the screen needs beyond a counter,
    /// because "port open" and "port open and generating right now" are different lines to a user
    /// watching a laptop wait. Reported by the servicer on the main actor, never from a socket queue,
    /// and dropped the moment the surface is no longer running.
    func noteTurn(active: Bool) {
        guard status.state == .running else { return }
        status.isServingTurn = active
    }

    func refusal(in decision: ShareStartDecision) -> ShareRefusal {
        if case .refused(let reason) = decision { return reason }
        return .alreadyRunning
    }
}
