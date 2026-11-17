import Foundation
import CairnChatDomain

/// The scan behind the "Scan local network" button.
///
/// Nothing here ever runs on its own: no scan at launch, no background scan, no timer. A scan
/// happens when the user presses the button, and the results are **drafts** — a found server is
/// not written to disk until the user saves it, so a scan can never add a server by itself.
/// Walking a subnet asking strangers for answers is exactly the thing an app should only do when
/// asked, which is also why the address range is the phone's own /24 and never anything public.
@MainActor
public final class LANDiscoveryService: ServerDiscovering {
    private let transport: any LANProbeTransporting
    /// Injectable so a host test can decide exactly what answers, on which address, with no
    /// socket involved. Defaults to the phone's real interface table.
    private let addressReader: @Sendable () -> [String]

    /// Production wiring: the phone's real interface table and real probes. Kept argument-free so
    /// the internal probe types stay internal — the App layer only ever needs `ServerDiscovering`.
    public convenience init() {
        self.init(transport: LANDiscoveryTransport()) { LocalIPv4Reader.privateAddresses() }
    }

    /// Test wiring: a fake transport decides what answers, and a fake address list decides the
    /// subnet, so the whole policy is provable on the host with no socket.
    init(
        transport: any LANProbeTransporting,
        addressReader: @escaping @Sendable () -> [String]
    ) {
        self.transport = transport
        self.addressReader = addressReader
    }

    public func discover(
        progress: @escaping @MainActor (LANDiscoveryProgress) -> Void
    ) async -> LANDiscoveryReport {
        let hosts = sweep()
        // No private address means the phone is not on a network worth scanning; the report says
        // so plainly rather than reporting an empty scan as "nothing found".
        guard !hosts.isEmpty else { return .empty }

        var hits: [ServerProbeHit] = []
        var failures = 0
        var probesIssued = 0
        var hostsDone: Set<String> = []
        let targets = LANDiscoveryPlan.primaryTargets()
        var queue = hosts.flatMap { host in targets.map { $0.probe(onHost: host) } }

        while !queue.isEmpty {
            if Task.isCancelled {
                return report(hostsDone: hostsDone.count, hits: hits, probesIssued: probesIssued, failures: failures, cancelled: true)
            }
            let wave = Array(queue.prefix(LANDiscoveryPlan.probeConcurrency))
            queue.removeFirst(wave.count)
            let outcomes = await run(wave)
            probesIssued += wave.count
            var fallbacks: [ServerProbe] = []
            for (probe, outcome) in outcomes {
                hostsDone.insert(probe.host)
                switch outcome {
                case .modelServer(let count):
                    hits.append(ServerProbeHit(probe: probe, modelCount: count))
                case .needsCredential:
                    hits.append(ServerProbeHit(probe: probe, needsCredential: true))
                case .notAModelServer:
                    fallbacks.append(LANDiscoveryPlan.fallbackTarget(forPort: probe.port).probe(onHost: probe.host))
                case .unreachable:
                    break
                case .failure:
                    failures += 1
                }
            }
            progress(LANDiscoveryProgress(hostsDone: hostsDone.count, hostsTotal: hosts.count))

            // Only a port that answered but did not know its own dialect gets asked again, in the
            // generic dialect. Nothing that refused is retried, so a full scan costs one extra
            // probe per open-and-unrecognised port and nothing more.
            guard !fallbacks.isEmpty else { continue }
            let secondPass = await run(fallbacks)
            probesIssued += fallbacks.count
            for (probe, outcome) in secondPass {
                switch outcome {
                case .modelServer(let count):
                    hits.append(ServerProbeHit(probe: probe, modelCount: count))
                case .needsCredential:
                    hits.append(ServerProbeHit(probe: probe, needsCredential: true))
                case .unreachable, .notAModelServer:
                    break
                case .failure:
                    failures += 1
                }
            }
        }

        return report(
            hostsDone: hostsDone.count,
            hits: hits,
            probesIssued: probesIssued,
            failures: failures,
            cancelled: false
        )
    }

    /// The /24 the phone is standing on, or empty. Never a public range, never another subnet.
    private func sweep() -> [String] {
        let read = addressReader()
        guard let base = read.first(where: { LANDiscoveryPlan.isScannable(host: $0) }) else {
            return []
        }
        return LANDiscoveryPlan.hostSweep(baseAddress: base)
    }

    /// One wave: a bounded task group, so at most `probeConcurrency` probes are in flight and a
    /// phone on Wi-Fi is never asked to hold two hundred half-open connections.
    private func run(_ probes: [ServerProbe]) async -> [(ServerProbe, LANProbeOutcome)] {
        guard !probes.isEmpty else { return [] }
        let transport = self.transport
        return await withTaskGroup(of: (ServerProbe, LANProbeOutcome).self) { group in
            for probe in probes {
                group.addTask { (probe, await transport.probe(probe)) }
            }
            var results: [(ServerProbe, LANProbeOutcome)] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    /// Counts only. A report deliberately carries no hostname of the phone, no interface name, and
    /// no response body — what a scan learned stays in the returned drafts the user agreed to see.
    private func report(
        hostsDone: Int,
        hits: [ServerProbeHit],
        probesIssued: Int,
        failures: Int,
        cancelled: Bool
    ) -> LANDiscoveryReport {
        LANDiscoveryReport(
            servers: LANDiscoveryPlan.servers(from: hits),
            hostsScanned: hostsDone,
            probesIssued: probesIssued,
            failures: failures,
            cancelled: cancelled
        )
    }
}
