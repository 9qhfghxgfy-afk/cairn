import XCTest
@testable import CairnChatDomain

/// The scan plan is pure, so the rules that keep a sweep polite and local are testable without a
/// socket: which addresses may be touched at all, how many probes may be in flight, and what an
/// empty result is allowed to claim.
final class LANDiscoveryPlanTests: XCTestCase {

    func testOnlyAPrivateIPv4IsScannable() {
        XCTAssertTrue(LANDiscoveryPlan.isScannable(host: "192.168.1.20"))
        XCTAssertTrue(LANDiscoveryPlan.isScannable(host: "10.8.0.1"), "a 10/8 network is a LAN too")
        XCTAssertFalse(LANDiscoveryPlan.isScannable(host: "127.0.0.1"), "nothing useful listens there")
        XCTAssertFalse(LANDiscoveryPlan.isScannable(host: "100.64.0.1"), "a mesh address is not this link")
        XCTAssertFalse(LANDiscoveryPlan.isScannable(host: "your-host.example.com"), "a name is not a sweep")
    }

    func testSweepIsOneSubnetAndSkipsTheDeviceItself() {
        let sweep = LANDiscoveryPlan.hostSweep(baseAddress: "192.168.1.20")
        XCTAssertEqual(sweep.count, 253)
        XCTAssertFalse(sweep.contains("192.168.1.20"))
        XCTAssertFalse(sweep.contains("192.168.1.0"))
        XCTAssertFalse(sweep.contains("192.168.1.255"))
        XCTAssertTrue(sweep.allSatisfy { $0.hasPrefix("192.168.1.") }, "a sweep never leaves the /24")
        // Nothing scannable means nothing to do, rather than a guess at another range.
        XCTAssertTrue(LANDiscoveryPlan.hostSweep(baseAddress: "127.0.0.1").isEmpty)
        XCTAssertTrue(LANDiscoveryPlan.hostSweep(baseAddress: "your-host.example.com").isEmpty)
    }

    func testProbesStayOnTheDeclaredPortsAndAbsolutePaths() {
        let targets = LANDiscoveryPlan.primaryTargets()
        XCTAssertFalse(targets.isEmpty)
        XCTAssertTrue(targets.contains { $0.port == 11434 })
        XCTAssertTrue(targets.contains { $0.port == 1234 })
        for host in LANDiscoveryPlan.hostSweep(baseAddress: "192.168.1.20").prefix(3) {
            for probe in LANDiscoveryPlan.probes(forHost: host) {
                XCTAssertEqual(probe.host, host)
                XCTAssertTrue(probe.path.hasPrefix("/"))
                XCTAssertFalse(probe.path.contains("/v0"))
            }
        }
        XCTAssertTrue(LANDiscoveryPlan.probes(forHost: "127.0.0.1").isEmpty)
    }

    func testConcurrencyIsBoundedSoASecondCannotOpenTheWholeSubnetAtOnce() {
        XCTAssertGreaterThan(LANDiscoveryPlan.probeConcurrency, 0)
        XCTAssertLessThanOrEqual(LANDiscoveryPlan.probeConcurrency, 16)
        XCTAssertGreaterThan(LANDiscoveryPlan.probeTimeoutSeconds, 0)
        XCTAssertLessThanOrEqual(LANDiscoveryPlan.probeTimeoutSeconds, 5)
    }

    func testHitsCollapseToOneRowPerAddressAndAPort() {
        let host = "192.168.1.20"
        let native = ServerProbeHit(
            probe: ServerProbe(host: host, port: 11434, path: "/api/tags", kind: .ollama),
            modelCount: 6
        )
        let duplicate = ServerProbeHit(
            probe: ServerProbe(host: host, port: 11434, path: "/v1/models", kind: .openAICompatible),
            needsCredential: true
        )
        let other = ServerProbeHit(
            probe: ServerProbe(host: "192.168.1.31", port: 1234, path: "/api/v1/models", kind: .lmStudio),
            modelCount: 2
        )

        let servers = LANDiscoveryPlan.servers(from: [native, duplicate, other])
        XCTAssertEqual(servers.count, 2)
        // The native hit named the backend, so the generic key-gated hit does not overwrite it.
        let found = servers.first { $0.host == host }
        XCTAssertEqual(found?.kind, .ollama)
        XCTAssertEqual(found?.modelCount, 6)
        XCTAssertFalse(found?.needsCredential ?? true)
        // Ordered by address, so the list does not shuffle between scans.
        XCTAssertEqual(servers.map(\.host), ["192.168.1.20", "192.168.1.31"])
        XCTAssertEqual(found?.draftProfile().kind, .ollama)
        XCTAssertEqual(found?.baseURLString, "http://192.168.1.20:11434")
    }

    func testAnEmptyScanOnlyBlamesThePermissionWhenNothingWasReached() {
        XCTAssertNil(LANDiscoveryPlan.emptyScanHint(serversFound: 1, hostsScanned: 253, failures: 20))
        XCTAssertTrue(
            LANDiscoveryPlan.emptyScanHint(serversFound: 0, hostsScanned: 0, failures: 0)?
                .contains("Wi-Fi") ?? false
        )
        XCTAssertTrue(
            LANDiscoveryPlan.emptyScanHint(serversFound: 0, hostsScanned: 253, failures: 700)?
                .contains("Local Network") ?? false
        )
        XCTAssertNotNil(LANDiscoveryPlan.emptyScanHint(serversFound: 0, hostsScanned: 253, failures: 0))
    }
}
