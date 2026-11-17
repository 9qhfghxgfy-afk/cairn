import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The scan behind the "Scan local network" button, run against a fake probe transport. What is
/// proved is the policy rather than the socket: the sweep stays inside the /24 the device is
/// standing on, keeps a bounded number of probes in flight, asks an unrecognised port exactly one
/// more question, never retries what simply refused, and collapses hits to one row per address and
/// port. The hints are part of the contract as well — a denied Local Network permission looks
/// exactly like every closed port, so an empty scan may only blame the permission when nothing at
/// all could be reached.
@MainActor
final class LANDiscoveryServiceTests: XCTestCase {

    /// The documented example LAN address, standing in for the phone's own interface address.
    private let phone = "192.168.1.20"
    /// One question per port on every usable host of one /24.
    private var sweepProbes: Int { 253 * LANDiscoveryPlan.ports.count }

    private func scan(
        _ transport: FakeProbeTransport,
        addresses: [String]? = nil,
        progress: ProgressLog? = nil
    ) async -> LANDiscoveryReport {
        let hosts = addresses ?? [phone]
        let service = LANDiscoveryService(transport: transport) { hosts }
        return await service.discover { tick in progress?.record(tick) }
    }

    func testASweepCoversTheOwnSlash24AndAsksEachPortOneQuestion() async throws {
        let transport = FakeProbeTransport()
        let report = await scan(transport)

        XCTAssertEqual(report.probesIssued, sweepProbes)
        XCTAssertEqual(report.hostsScanned, 253)
        XCTAssertTrue(transport.probes.allSatisfy { $0.host.hasPrefix("192.168.1.") }, "a scan never leaves the /24")
        XCTAssertFalse(transport.probes.contains { $0.host == phone }, "the phone is not probed for its own models")
        XCTAssertFalse(transport.probes.contains { $0.host.hasSuffix(".0") }, "the network address is not a host")
        XCTAssertEqual(Set(transport.probes.map(\.port)), Set(LANDiscoveryPlan.ports))
        XCTAssertEqual(
            Set(transport.probes.map { "\($0.host):\($0.port):\($0.path)" }).count,
            transport.probes.count,
            "one probe per address and port — a sweep must not ask the same question twice"
        )
    }

    /// No private address means the phone is not on a network worth sweeping, and saying so is
    /// different from reporting an empty scan. A mesh address does not count: the scan is about the
    /// link the phone is standing on, not about reaching through a tunnel.
    func testNoPrivateAddressMeansNoSweepAtAll() async throws {
        for addresses in [["100.64.1.2"], ["127.0.0.1"], []] {
            let transport = FakeProbeTransport()
            let report = await scan(transport, addresses: addresses)
            XCTAssertTrue(transport.probes.isEmpty, "no scannable address, so no probe is issued at all")
            XCTAssertEqual(report, .empty)
            XCTAssertTrue(report.localNetworkHint?.contains("Wi-Fi") ?? false, "the honest reason is the network, not the permission")
        }
    }

    func testProbesStayBoundedInFlight() async throws {
        let transport = FakeProbeTransport(probeDelayNanoseconds: 2_000_000)
        let report = await scan(transport)

        XCTAssertLessThanOrEqual(transport.peakConcurrency, LANDiscoveryPlan.probeConcurrency)
        XCTAssertGreaterThan(transport.peakConcurrency, 1, "a wave really is in flight together, not one by one")
        XCTAssertEqual(report.probesIssued, sweepProbes, "bounded means paced, not truncated")
    }

    /// A timeout, a down network, or a denied permission is not an answer about the port, so it is
    /// counted as unanswered — and it is not retried, which is what keeps a scan from looping.
    func testUnansweredProbesAreCountedAndNeverRetried() async throws {
        let transport = FakeProbeTransport(otherwise: .failure)
        let report = await scan(transport)

        XCTAssertEqual(report.failures, sweepProbes)
        XCTAssertEqual(transport.probes.count, sweepProbes, "nothing that went unanswered is asked again")
        XCTAssertTrue(report.localNetworkHint?.contains("Local Network") ?? false)
    }

    func testProgressCountsUpSoTheBarNeverSpinsOrShrinks() async throws {
        let log = ProgressLog()
        let waves = (sweepProbes + LANDiscoveryPlan.probeConcurrency - 1) / LANDiscoveryPlan.probeConcurrency
        let report = await scan(FakeProbeTransport(), progress: log)

        XCTAssertEqual(log.ticks.count, waves, "one tick per wave, which is what makes the bar move steadily")
        XCTAssertTrue(log.ticks.allSatisfy { $0.hostsTotal == 253 }, "the total is the whole /24 from the first tick")
        XCTAssertTrue(
            zip(log.ticks.dropFirst(), log.ticks).allSatisfy { $1.hostsDone <= $0.hostsDone },
            "a progress bar never goes backwards"
        )
        XCTAssertEqual(log.last.hostsDone, 253)
        XCTAssertEqual(log.last.fraction, 1.0)
        XCTAssertEqual(report.hostsScanned, log.last.hostsDone, "the screen and the report agree on what was scanned")
    }

    /// A server answering on three ports is three rows — one per address and port — and each row is
    /// a draft with no key, because a discovered server has none until the user types one.
    func testFoundServersComeBackAsOneRowPerAddressAndPort() async throws {
        let host = "192.168.1.10"
        let transport = FakeProbeTransport(answers: [
            "\(host):11434": .modelServer(modelCount: 6),
            "\(host):1234": .modelServer(modelCount: 2),
            "\(host):8080": .needsCredential,
        ])

        let report = await scan(transport)

        XCTAssertEqual(report.servers.count, 3)
        XCTAssertEqual(report.servers.map(\.port), [1234, 8080, 11434], "ordered, so the list does not shuffle between scans")
        XCTAssertEqual(report.servers.map(\.kind), [.lmStudio, .openAICompatible, .ollama])
        XCTAssertNil(report.localNetworkHint, "a scan that found servers has nothing to explain")

        let ollamaRow = try XCTUnwrap(report.servers.first { $0.port == 11434 })
        XCTAssertEqual(ollamaRow.modelCount, 6)
        let draft = ollamaRow.draftProfile()
        XCTAssertEqual(draft.kind, .ollama)
        XCTAssertEqual(draft.baseURLString, "http://\(host):11434", "a found server on the LAN is addressed over plain http")
        XCTAssertFalse(draft.hasBearerToken, "a discovered server never arrives with a key")
        XCTAssertTrue(draft.enabled)
        XCTAssertFalse(draft.publicInternetOptIn, "a machine on this link is not a public-internet profile")
    }

    /// A port that answers but does not know its own dialect gets asked once more in the generic
    /// one, and is then offered as what it actually answered as — one row, not two.
    func testAnUnrecognisedPortIsAskedOnceMoreInTheGenericDialect() async throws {
        let host = "192.168.1.5"
        let transport = FakeProbeTransport(answers: [
            "\(host):11434:/api/tags": .notAModelServer,
            "\(host):11434:/v1/models": .needsCredential,
        ])

        let report = await scan(transport)
        let asked = transport.askedOf(host, port: 11434)

        XCTAssertEqual(asked.count, 2, "its own endpoint once, then the generic listing once, never a third")
        XCTAssertEqual(asked.first?.path, "/api/tags")
        XCTAssertEqual(asked.last?.path, "/v1/models")
        XCTAssertEqual(report.probesIssued, sweepProbes + 1, "a full scan costs one extra probe per open-and-unrecognised port")
        XCTAssertEqual(report.servers.count, 1)
        let row = try XCTUnwrap(report.servers.first)
        XCTAssertEqual(row.kind, .openAICompatible, "offered as what answered, not as what was hoped for")
        XCTAssertTrue(row.needsCredential, "a port that refuses without a key is still a server worth adding")
    }

    /// Stopping is something the user asks for, and a stopped scan hands the screen nothing that
    /// could be saved. The stop is observed mid-sweep, so the cancellation path is really taken.
    func testAStoppedScanReportsItWasStoppedAndHandsOverNothingToSave() async throws {
        let transport = FakeProbeTransport(probeDelayNanoseconds: 2_000_000)
        transport.cancelAfterProbes = 30
        let hosts = [phone]
        let service = LANDiscoveryService(transport: transport) { hosts }

        let scanTask = Task { await service.discover { _ in } }
        transport.cancelOuterTask = { scanTask.cancel() }
        let report = await scanTask.value

        XCTAssertTrue(report.cancelled, "the fake cancelled mid-sweep, so this is the stopped path")
        XCTAssertTrue(report.servers.isEmpty, "a stopped scan offers no drafts")
        XCTAssertLessThan(report.probesIssued, sweepProbes, "stopping actually stops rather than finishing quietly")
    }

    /// "Nothing found" and "nothing could be reached" are different facts, and only the second one
    /// is worth naming the Local Network permission — a denial fails every probe in a way that is
    /// indistinguishable from a closed port, so the honesty has to be in which hint is shown.
    func testTheHintIsHonestAboutWhatWasActuallyReached() async throws {
        let refused = FakeProbeTransport(otherwise: .unreachable)
        let quiet = await scan(refused)
        XCTAssertEqual(quiet.failures, 0, "a refusal is an answer about the port, not a failure to ask")
        XCTAssertTrue(quiet.localNetworkHint?.contains("127.0.0.1") ?? false, "the fix is how the server is bound, not the permission")

        let partial = FakeProbeTransport(
            answers: ["192.168.1.10:11434": .modelServer(modelCount: 4)],
            otherwise: .failure
        )
        let found = await scan(partial)
        XCTAssertEqual(found.servers.count, 1)
        XCTAssertNil(found.localNetworkHint, "a scan that found a server has nothing to blame")
    }
}

