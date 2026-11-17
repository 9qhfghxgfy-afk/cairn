import Foundation
import CairnChatDomain
@testable import CairnProviderRemote

/// A fake probe transport for the LAN scan: it decides exactly which address and port answer,
/// records every probe it was asked for, and counts how many were in flight at one instant. No
/// socket, so the whole scan policy is provable on a runner that has no LAN with a model server on
/// it — which is every runner there is.
///
/// Keys are `host:port`, or `host:port:path` to answer one probe on a port rather than the whole
/// port, which is what lets a test say "Ollama's own endpoint refused, the generic listing
/// answered". Every address a test writes is a documented example
/// `Scripts/check-hostname.sh` allow-lists; the rest of the sweep takes `otherwise`.
final class FakeProbeTransport: LANProbeTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: LANProbeOutcome]
    private let otherwise: LANProbeOutcome
    private let delayNanoseconds: UInt64
    private var seen: [ServerProbe] = []
    private var inFlight = 0
    private var peak = 0
    private var taken = 0

    /// Set once the scan's Task exists, so a test can stop a sweep mid-flight without racing it.
    var cancelOuterTask: (@Sendable () -> Void)?
    /// Cancelling after this many probes makes a stopped scan deterministic rather than timed.
    var cancelAfterProbes: Int?

    init(
        answers: [String: LANProbeOutcome] = [:],
        otherwise: LANProbeOutcome = .unreachable,
        probeDelayNanoseconds: UInt64 = 0
    ) {
        self.answers = answers
        self.otherwise = otherwise
        self.delayNanoseconds = probeDelayNanoseconds
    }

    func probe(_ probe: ServerProbe) async -> LANProbeOutcome {
        noteStart(of: probe)
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        let outcome = answer(for: probe)
        noteFinish()
        return outcome
    }

    var probes: [ServerProbe] { lock.lock(); defer { lock.unlock() }; return seen }
    var probesTaken: Int { lock.lock(); defer { lock.unlock() }; return taken }
    /// The most probes ever open at one instant, which is what "bounded" has to mean.
    var peakConcurrency: Int { lock.lock(); defer { lock.unlock() }; return peak }

    func askedOf(_ host: String, port: Int) -> [ServerProbe] {
        probes.filter { $0.host == host && $0.port == port }
    }

    private func answer(for probe: ServerProbe) -> LANProbeOutcome {
        lock.lock()
        let exact = "\(probe.host):\(probe.port):\(probe.path)"
        let outcome = answers[exact] ?? answers["\(probe.host):\(probe.port)"] ?? otherwise
        lock.unlock()
        return outcome
    }

    private func noteStart(of probe: ServerProbe) {
        lock.lock()
        seen.append(probe)
        taken += 1
        inFlight += 1
        peak = max(peak, inFlight)
        let shouldCancel = cancelAfterProbes != nil && taken == cancelAfterProbes
        let hook = cancelOuterTask
        lock.unlock()
        if shouldCancel { hook?() }
    }

    private func noteFinish() {
        lock.lock()
        inFlight -= 1
        lock.unlock()
    }
}

/// Where a scan's progress ticks land. A box rather than a captured local, so the test holds one
/// value across a task boundary instead of asking Swift 6 to excuse mutable state crossing it.
@MainActor
final class ProgressLog {
    var ticks: [LANDiscoveryProgress] = []

    func record(_ progress: LANDiscoveryProgress) { ticks.append(progress) }

    var last: LANDiscoveryProgress { ticks.last ?? LANDiscoveryProgress(hostsDone: 0, hostsTotal: 0) }
}
