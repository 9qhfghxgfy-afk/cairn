import XCTest
@testable import CairnChatDomain

/// Which engine a mode has to be answered by.
///
/// These are the rules that used not to exist: choosing "On device" stored the word and left the
/// session answering from the server it was already pointed at. A mode that changes nothing is a
/// control that lies, so the routing is pure and proved here rather than trusted to a view.
final class ModeRoutingTests: XCTestCase {
    private let engines = ["mock", "on-device.apple", "remote:AAAA"]
    private let kinds: [String: EngineKind] = [
        "mock": .standIn,
        "on-device.apple": .localModel,
        "remote:AAAA": .server
    ]

    func testOnDeviceModeNamesTheOnDeviceEngine() {
        XCTAssertEqual(
            ModeRouting.engineID(
                for: .onDeviceOnly,
                engines: engines,
                kinds: kinds,
                current: "remote:AAAA"
            ),
            "on-device.apple"
        )
    }

    func testRemoteModeNamesTheChosenServerRatherThanTheFirstEngineInTheList() {
        let profileID = UUID()
        XCTAssertEqual(
            ModeRouting.engineID(
                for: .remoteOnly,
                engines: ["mock", "remote:BBBB", RemoteEngineID.make(profileID: profileID)],
                kinds: [
                    "mock": .standIn,
                    "remote:BBBB": .server,
                    RemoteEngineID.make(profileID: profileID): .server
                ],
                current: "on-device.apple",
                preferredRemote: RemoteEngineID.make(profileID: profileID)
            ),
            RemoteEngineID.make(profileID: profileID)
        )
    }

    /// A stub that reports `.onDevice` — which is honest about sending nothing — is not a model, and
    /// pointing a chat at it would be a switch that reports a mode it does not honour.
    func testOnDeviceModeNeverRoutesToTheStandIn() {
        XCTAssertNil(
            ModeRouting.engineID(
                for: .onDeviceOnly,
                engines: ["mock", "remote:AAAA"],
                kinds: ["mock": .standIn, "remote:AAAA": .server],
                current: "remote:AAAA"
            )
        )
    }

    func testAModeWithNothingBehindItChangesNothing() {
        XCTAssertNil(
            ModeRouting.engineID(
                for: .remoteOnly,
                engines: ["mock", "on-device.apple"],
                kinds: ["mock": .standIn, "on-device.apple": .localModel],
                current: "on-device.apple"
            )
        )
    }

    /// Already on the engine the mode wants: no churn, because repointing an engine also reloads its
    /// model list, and a reload that changes nothing is a spinner for nothing.
    func testAModeAlreadyHonouredRepointsNothing() {
        XCTAssertNil(
            ModeRouting.engineID(
                for: .onDeviceOnly,
                engines: engines,
                kinds: kinds,
                current: "on-device.apple"
            )
        )
    }

    /// A hybrid turn names both engines in its own plan and asks both, so its mode never repoints the
    /// session — the session's engine is only what the panels' labels say.
    func testHybridModesRepointNoEngine() {
        for mode in [InferenceMode.hybridParallel, .hybridSynthesized] {
            XCTAssertNil(
                ModeRouting.engineID(for: mode, engines: engines, kinds: kinds, current: "mock")
            )
            XCTAssertNil(ModeRouting.requiredKind(for: mode))
        }
    }

    func testPlainModesEachInsistOnOneKind() {
        XCTAssertEqual(ModeRouting.requiredKind(for: .onDeviceOnly), .localModel)
        XCTAssertEqual(ModeRouting.requiredKind(for: .remoteOnly), .server)
    }

    /// An id the map says nothing about is a stand-in, never a model — which is the safe reading of a
    /// freshly registered engine that has not declared itself.
    func testAnUnknownEngineKindIsReadAsAStandIn() {
        let defaultKind = MockStreamingProvider().engineKind
        XCTAssertEqual(defaultKind, .standIn)
        XCTAssertEqual(MockStreamingProvider().networkClass, .onDevice)
    }
}
