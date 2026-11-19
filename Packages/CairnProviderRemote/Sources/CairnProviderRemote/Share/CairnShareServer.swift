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
    private let engineSource: @Sendable () -> [any InferenceProvider]
    private let addressSource: @Sendable () -> String?
    var table = ShareEngineTable()
    var token = ""
    var turnTasks: [Task<Void, Never>] = []
    var openClients = 0

    public init(
        engines: @escaping @Sendable () -> [any InferenceProvider],
        addressSource: @escaping @Sendable () -> String? = { LocalIPv4Reader.primaryAddress() }
    ) {
        self.transport = ShareSocketTransport()
        self.engineSource = engines
        self.addressSource = addressSource
        transport.onConnection = { [weak self] socket in
            Task { @MainActor in self?.accept(socket) }
        }
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
        guard await transport.start(address: address, port: port) else {
            // The bind failed. Which system error it was is not reportable here — a failure string can
            // carry an address — so the screen gets the code that describes a port that will not open.
            status = ShareServerStatus(state: .failed, port: port, servedModelIDs: built.servedIDs, failure: .portUnusable)
            return .refused(.portUnusable)
        }

        self.table = built
        self.token = token
        status = ShareServerStatus(state: .running, port: port, servedModelIDs: built.servedIDs, boundAddress: address)
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

    func refusal(in decision: ShareStartDecision) -> ShareRefusal {
        if case .refused(let reason) = decision { return reason }
        return .alreadyRunning
    }
}
