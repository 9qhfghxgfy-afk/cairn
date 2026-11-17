import Foundation

/// One address + port + path the scanner asks a question of.
public struct ServerProbe: Sendable, Equatable, Hashable {
    public var host: String
    public var port: Int
    public var path: String
    public var kind: ServerProfileKind

    public init(host: String, port: Int, path: String, kind: ServerProfileKind) {
        self.host = host
        self.port = port
        self.path = path
        self.kind = kind
    }
}

/// What came back from one probe. `needsCredential` is a positive result: the port is served by
/// something that refuses requests without a key, which is a server worth adding.
public struct ServerProbeHit: Sendable, Equatable {
    public var probe: ServerProbe
    public var modelCount: Int?
    public var needsCredential: Bool

    public init(probe: ServerProbe, modelCount: Int? = nil, needsCredential: Bool = false) {
        self.probe = probe
        self.modelCount = modelCount
        self.needsCredential = needsCredential
    }

    public var host: String { probe.host }
    public var port: Int { probe.port }
    public var kind: ServerProfileKind { probe.kind }
}

/// A server found on the local network, offered as a draft the user confirms before it is saved.
public struct DiscoveredServer: Sendable, Equatable, Identifiable {
    public var host: String
    public var port: Int
    public var kind: ServerProfileKind
    public var modelCount: Int?
    public var needsCredential: Bool

    public init(
        host: String,
        port: Int,
        kind: ServerProfileKind,
        modelCount: Int? = nil,
        needsCredential: Bool = false
    ) {
        self.host = host
        self.port = port
        self.kind = kind
        self.modelCount = modelCount
        self.needsCredential = needsCredential
    }

    public var id: String { "\(host):\(port)" }

    /// A found server is a LAN server, so it is addressed over plain http — the same rule every
    /// other private profile follows.
    public var baseURLString: String { "http://\(host):\(port)" }

    public var suggestedName: String { "\(kind.displayName) · \(host):\(port)" }

    /// The Add-server draft this result prefills. It is a draft: nothing is stored until the user
    /// saves it, so a scan can never add a server on its own.
    public func draftProfile(now: Date = Date()) -> ServerProfile {
        ServerProfile(
            name: suggestedName,
            kind: kind,
            baseURLString: baseURLString,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )
    }
}

/// Progress of a scan, so the screen can say how far it has got instead of spinning.
public struct LANDiscoveryProgress: Sendable, Equatable {
    public var hostsDone: Int
    public var hostsTotal: Int

    public init(hostsDone: Int, hostsTotal: Int) {
        self.hostsDone = hostsDone
        self.hostsTotal = hostsTotal
    }

    public var fraction: Double {
        hostsTotal == 0 ? 0 : Double(hostsDone) / Double(hostsTotal)
    }
}

/// The result of one user-initiated scan. Counts are typed metadata only: no host, no response
/// body, nothing that could name a device the user did not add.
public struct LANDiscoveryReport: Sendable, Equatable {
    public var servers: [DiscoveredServer]
    public var hostsScanned: Int
    public var probesIssued: Int
    public var failures: Int
    public var cancelled: Bool

    public init(
        servers: [DiscoveredServer] = [],
        hostsScanned: Int = 0,
        probesIssued: Int = 0,
        failures: Int = 0,
        cancelled: Bool = false
    ) {
        self.servers = servers
        self.hostsScanned = hostsScanned
        self.probesIssued = probesIssued
        self.failures = failures
        self.cancelled = cancelled
    }

    public static let empty = LANDiscoveryReport()

    public var localNetworkHint: String? {
        LANDiscoveryPlan.emptyScanHint(
            serversFound: servers.count,
            hostsScanned: hostsScanned,
            failures: failures
        )
    }
}

/// The local-network scan, behind a boundary so `CairnAppUI` imports no networking. The caller
/// cancels by cancelling the Task; the service checks for cancellation between waves.
@MainActor
public protocol ServerDiscovering: AnyObject {
    func discover(
        progress: @escaping @MainActor (LANDiscoveryProgress) -> Void
    ) async -> LANDiscoveryReport
}
