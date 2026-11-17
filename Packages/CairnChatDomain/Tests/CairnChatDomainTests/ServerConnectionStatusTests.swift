import XCTest
@testable import CairnChatDomain

/// The dot is derived on every read, and the order of the rules is the whole point: a server that
/// cannot be reached must never look live because something remembered an old success.
final class ServerConnectionStatusTests: XCTestCase {

    private func lanProfile(enabled: Bool = true) -> ServerProfile {
        ServerProfile(
            name: "Home box",
            kind: .ollama,
            baseURLString: "http://192.168.1.20:11434",
            enabled: enabled,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// A hosted server with no outbound permission: same shape as a real cloud profile, so
    /// `usableNow` is false for the reason that matters — traffic would leave the device.
    private func cloudProfile(optIn: Bool = false) -> ServerProfile {
        var made = ServerProfile(
            name: "Hosted",
            kind: .ollamaCloud,
            baseURLString: "https://ollama.com",
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        made.publicInternetOptIn = optIn
        return made
    }

    private let connected = RemoteTestOutcome.connected(
        version: "0.5",
        modelCount: 4,
        latencyMilliseconds: 12
    )

    func testATestInFlightOutranksEverything() {
        let status = ServerConnectionStatus.derive(
            profile: lanProfile(enabled: false),
            outcome: connected,
            isTesting: true
        )
        XCTAssertEqual(status, .checking)
    }

    func testAServerThatCannotAnswerIsInertEvenWithAPastSuccess() {
        let blocked = [lanProfile(enabled: false), cloudProfile(optIn: false)]
        for subject in blocked {
            let status = ServerConnectionStatus.derive(
                profile: subject,
                outcome: connected,
                isTesting: false
            )
            XCTAssertEqual(status, .inert, "\(subject.name) must not look connected")
            XCTAssertEqual(status.shortLabel, "Inert")
        }
    }

    func testNothingTestedIsNotTheSameThingAsFailure() {
        let status = ServerConnectionStatus.derive(
            profile: lanProfile(),
            outcome: nil,
            isTesting: false
        )
        XCTAssertEqual(status, .unchecked)
        XCTAssertFalse(status.isOnline)
    }

    func testASuccessfulTestReportsWhatTheServerItselfSaid() {
        let status = ServerConnectionStatus.derive(
            profile: lanProfile(),
            outcome: connected,
            isTesting: false
        )
        XCTAssertEqual(status, .online(modelCount: 4, latencyMilliseconds: 12))
        XCTAssertTrue(status.isOnline)
        XCTAssertEqual(status.shortLabel, "Connected")
    }

    func testAPermittedCloudServerIsAllowedToLookConnected() {
        let status = ServerConnectionStatus.derive(
            profile: cloudProfile(optIn: true),
            outcome: connected,
            isTesting: false
        )
        XCTAssertTrue(status.isOnline, "opting in is what makes a hosted server usable")
    }

    func testAFailedTestKeepsTheOutcomeOwnHint() {
        let status = ServerConnectionStatus.derive(
            profile: lanProfile(),
            outcome: .timedOut,
            isTesting: false
        )
        guard case .failed(let message) = status else {
            return XCTFail("expected a failure that names what went wrong")
        }
        XCTAssertFalse(message.isEmpty)
    }
}
