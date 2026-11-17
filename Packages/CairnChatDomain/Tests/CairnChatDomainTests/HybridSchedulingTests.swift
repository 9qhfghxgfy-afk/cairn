import XCTest
@testable import CairnChatDomain

/// The residency rule as a pure function: what may run together, in what order, and when a
/// release is owed. Proven on the host, because a phone cannot be trusted to have enforced it.
final class HybridSchedulingTests: XCTestCase {

    func testRemoteCandidatesShareOneConcurrentGroup() {
        let groups = HybridScheduling.candidateGroups(networkClasses: [.privateLan, .publicInternet])
        XCTAssertEqual(groups, [HybridRunGroup(indexes: [0, 1], concurrent: true)])
    }

    func testOneOnDeviceSideStillRunsAlongsideTheRemotes() {
        let groups = HybridScheduling.candidateGroups(networkClasses: [.onDevice, .privateLan])
        XCTAssertEqual(groups, [HybridRunGroup(indexes: [0, 1], concurrent: true)])
    }

    func testTwoOnDeviceSidesNeverShareAGroupByDefault() {
        let groups = HybridScheduling.candidateGroups(networkClasses: [.onDevice, .privateLan, .onDevice])
        XCTAssertEqual(groups, [
            HybridRunGroup(indexes: [1], concurrent: false),
            HybridRunGroup(indexes: [0], concurrent: false),
            HybridRunGroup(indexes: [2], concurrent: false),
        ])
    }

    func testTwoOnDeviceSidesShareAGroupOnlyWhenTheGateReportsRoom() {
        let groups = HybridScheduling.candidateGroups(
            networkClasses: [.onDevice, .onDevice],
            allowsTwoOnDeviceModelsResident: true
        )
        XCTAssertEqual(groups, [HybridRunGroup(indexes: [0, 1], concurrent: true)])
    }

    func testReleaseIsOwedOnlyAfterOnDeviceWork() {
        let classes: [NetworkClass] = [.privateLan, .onDevice]
        XCTAssertTrue(HybridScheduling.groupRanOnDevice(HybridRunGroup(indexes: [1], concurrent: false), networkClasses: classes))
        XCTAssertFalse(HybridScheduling.groupRanOnDevice(HybridRunGroup(indexes: [0], concurrent: false), networkClasses: classes))
    }

    func testSynthesisNeedsAReleaseOnlyWhenItIsOnDeviceAfterOnDeviceWork() {
        XCTAssertTrue(HybridScheduling.synthesisNeedsRelease(synthesizerClass: .onDevice, candidatesRanOnDevice: true))
        XCTAssertFalse(HybridScheduling.synthesisNeedsRelease(synthesizerClass: .privateLan, candidatesRanOnDevice: true))
        XCTAssertFalse(HybridScheduling.synthesisNeedsRelease(synthesizerClass: .onDevice, candidatesRanOnDevice: false))
    }

    func testSynthesizerDefaultsToTheRemoteSide() {
        let plan = HybridPlan(candidates: [
            HybridCandidate(engineID: "local", modelID: "on-device-model"),
            HybridCandidate(engineID: "lan", modelID: "server-model"),
        ])
        let chosen = HybridScheduling.resolveSynthesizer(plan: plan, networkClasses: [.onDevice, .privateLan])
        XCTAssertEqual(chosen?.engineID, "lan")
    }

    func testSynthesizerFallsBackToOnDeviceOnlyWhenNothingElseExists() {
        let plan = HybridPlan(candidates: [
            HybridCandidate(engineID: "local-a", modelID: "model-a"),
            HybridCandidate(engineID: "local-b", modelID: "model-b"),
        ])
        let chosen = HybridScheduling.resolveSynthesizer(plan: plan, networkClasses: [.onDevice, .onDevice])
        XCTAssertEqual(chosen?.engineID, "local-a")
    }

    func testAChosenSynthesizerBeatsTheDefault() {
        let plan = HybridPlan(
            candidates: [
                HybridCandidate(engineID: "lan", modelID: "server-model"),
                HybridCandidate(engineID: "local", modelID: "on-device-model"),
            ],
            synthesizer: HybridCandidate(engineID: "local", modelID: "on-device-model")
        )
        let chosen = HybridScheduling.resolveSynthesizer(plan: plan, networkClasses: [.privateLan, .onDevice])
        XCTAssertEqual(chosen?.id, "local|on-device-model")
    }
}