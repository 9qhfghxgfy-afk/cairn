import Foundation

/// The pure rules behind the local-network scan: which ports, which backend is expected on each,
/// which addresses may be probed at all, and what to say when nothing answers.
///
/// The scan is bounded by construction rather than by a limit imposed on the user: it covers the
/// /24 the phone is actually attached to, it never wanders onto a public address, it asks one
/// question per port, and it keeps a fixed number of probes in flight so a phone on Wi-Fi is not
/// flooded. Nothing here opens a socket, so the whole policy is unit-testable on the host with
/// documented example addresses.
public enum LANDiscoveryPlan {
    /// Ollama, LM Studio, and the usual OpenAI-compatible port (llama.cpp's server, LM Studio's
    /// alternative, most container images). These are the vendors' own defaults, not invented ones.
    public static let ports: [Int] = [11434, 1234, 8080]

    /// Probes in flight at once. Enough to sweep a /24 in seconds on a home LAN, few enough that
    /// a phone does not saturate its own Wi-Fi or trip a router's connection tracking.
    public static let probeConcurrency: Int = 12

    /// A LAN answer arrives in milliseconds. Anything slower than this is a host that is not
    /// there, and waiting longer only makes the scan feel frozen.
    public static let probeTimeoutSeconds: TimeInterval = 1.5

    public struct Target: Sendable, Equatable {
        public var port: Int
        public var path: String
        public var kind: ServerProfileKind

        public init(port: Int, path: String, kind: ServerProfileKind) {
            self.port = port
            self.path = path
            self.kind = kind
        }

        public func probe(onHost host: String) -> ServerProbe {
            ServerProbe(host: host, port: port, path: path, kind: kind)
        }
    }

    /// One probe per port: the endpoint that port's usual server publishes.
    public static func primaryTargets() -> [Target] {
        ports.map { port in
            switch port {
            case 11434: return Target(port: port, path: "/api/tags", kind: .ollama)
            case 1234: return Target(port: port, path: "/api/v1/models", kind: .lmStudio)
            default: return Target(port: port, path: "/v1/models", kind: .openAICompatible)
            }
        }
    }

    /// Asked only of a port that answered but did not recognise its expected dialect: an
    /// OpenAI-compatible server bound to a non-default port is still OpenAI-compatible.
    public static func fallbackTarget(forPort port: Int) -> Target {
        Target(port: port, path: "/v1/models", kind: .openAICompatible)
    }

    /// Only a real, private, non-loopback IPv4 gets probed.
    ///
    /// `.local` and unqualified names are excluded because there is no range to sweep behind a
    /// name — that address belongs in the Add-server field, not in a sweep. A VPN address is
    /// excluded because the scan is about the link the phone is standing on: reaching through a
    /// tunnel is a profile the user chose, not something to go looking for. Loopback is excluded
    /// because nothing useful can listen there on iOS.
    public static func isScannable(host: String) -> Bool {
        guard NetworkClassRouting.classify(host: host) == .privateLan else { return false }
        guard octets(of: host) != nil else { return false }
        return !host.hasPrefix("127.")
    }

    /// Every usable host address in the /24 of `baseAddress`, excluding the device's own address
    /// and the network address. Empty for anything but a scannable IPv4.
    public static func hostSweep(baseAddress: String) -> [String] {
        guard isScannable(host: baseAddress), let octets = octets(of: baseAddress) else { return [] }
        let prefix = "\(octets[0]).\(octets[1]).\(octets[2])"
        return (1...254).map { "\(prefix).\($0)" }.filter { $0 != baseAddress }
    }

    public static func probes(forHost host: String) -> [ServerProbe] {
        guard isScannable(host: host) else { return [] }
        return primaryTargets().map { $0.probe(onHost: host) }
    }

    /// Collapses hits to one row per address + port and orders them so the list is stable between
    /// scans rather than shuffled by arrival order.
    public static func servers(from hits: [ServerProbeHit]) -> [DiscoveredServer] {
        var byId: [String: DiscoveredServer] = [:]
        for hit in hits {
            let server = DiscoveredServer(
                host: hit.host,
                port: hit.port,
                kind: hit.kind,
                modelCount: hit.modelCount,
                needsCredential: hit.needsCredential
            )
            // A native-endpoint hit identifies the backend better than the generic listing does,
            // so a key-gated fallback hit never overwrites one that already named the server.
            if let existing = byId[server.id], !existing.needsCredential, server.needsCredential {
                continue
            }
            byId[server.id] = server
        }
        return byId.values.sorted { lhs, rhs in
            let left = sortKey(lhs.host), right = sortKey(rhs.host)
            if left != right { return left < right }
            if lhs.host != rhs.host { return lhs.host < rhs.host }
            return lhs.port < rhs.port
        }
    }

    /// What an empty scan actually means, in order of likelihood. A Local Network denial is
    /// indistinguishable from a closed port at the socket level — every probe simply fails — so
    /// the only honest signal is "nothing was reachable at all", and that is when the permission
    /// hint is worth showing.
    public static func emptyScanHint(
        serversFound: Int,
        hostsScanned: Int,
        failures: Int
    ) -> String? {
        guard serversFound == 0 else { return nil }
        if hostsScanned == 0 {
            return "This device has no local-network address to scan. Turn on Wi-Fi or join your "
                + "network, then scan again — Cairn only looks on the network your phone is on."
        }
        if failures == 0 {
            return "Nothing answered on the usual model-server ports. Check that the server is "
                + "running and bound to the network rather than only to 127.0.0.1."
        }
        return "Nothing could be reached. If iOS asked for Local Network access and you denied "
            + "it, allow it in the Settings app under Cairn → Local Network, then scan again: a "
            + "denial blocks every connection to your own network."
    }

    // MARK: - Address helpers

    private static func octets(of host: String) -> [Int]? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part), (0...255).contains(value) else { return nil }
            parsed.append(value)
        }
        return parsed
    }

    /// Numeric ordering for an IPv4 literal; anything unexpected sorts last but stays stable.
    private static func sortKey(_ host: String) -> Int {
        guard let parts = octets(of: host) else { return Int.max }
        return ((parts[0] * 256 + parts[1]) * 256 + parts[2]) * 256 + parts[3]
    }
}

