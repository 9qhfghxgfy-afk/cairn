import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The one place in the project that reads a `URLError`, pinned case by case.
///
/// A wrong read here does not crash — it prints the wrong sentence into the UI and sends the user to the
/// wrong setting. So every code gets its own assertion, and the guess gets its own too: an errno under the
/// POSIX domain is read as the Local Network refusal, the same URL code without that evidence is not, and an
/// errno from a different domain or a different number is not either. These assert what this file *decides*
/// to do with the evidence it is handed; they do not assert what any iOS version actually reports, which
/// stays on the device checklist.
final class WebSearchFailureTransportTests: XCTestCase {

    private func read(_ error: any Error) -> WebSearchFailure { WebSearchFailure.transport(error) }

    /// A connection failure with an errno planted underneath it, which is the shape the refusal
    /// has been reported with.
    private func refusal(underDomain domain: String, code: Int) -> URLError {
        URLError(.cannotConnectToHost, userInfo: [NSUnderlyingErrorKey: NSError(domain: domain, code: code)])
    }

    // MARK: - What a thrown error means

    func testATimeoutKeepsItsOwnName() {
        XCTAssertEqual(read(URLError(.timedOut)), .timedOut)
    }

    func testAnAddressThatCannotBeRequestedIsAnEndpointProblemNotAnOutage() {
        XCTAssertEqual(read(URLError(.unsupportedURL)), .invalidEndpoint)
        XCTAssertEqual(read(URLError(.badURL)), .invalidEndpoint)
    }

    func testEveryCertificateFailureIsSaidAsHttpsBeingRequired() {
        let codes: [URLError.Code] = [
            .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
        ]
        for code in codes {
            XCTAssertEqual(read(URLError(code)), .httpsRequired)
        }
    }

    func testAPermissionErrnoUnderneathReadsAsTheLocalNetworkRefusal() {
        XCTAssertEqual(read(refusal(underDomain: NSPOSIXErrorDomain, code: 1)), .localNetworkDenied)
        XCTAssertEqual(
            read(URLError(.networkConnectionLost,
                          userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 1)])),
            .localNetworkDenied
        )
    }

    func testAFailureThatOnlyLooksLikeARefusalIsNotClaimedAsPermission() {
        // Right number, wrong domain.
        XCTAssertEqual(read(refusal(underDomain: NSCocoaErrorDomain, code: 1)), .unreachable)
        // Right domain, wrong number: ECONNREFUSED is a closed port, not a permission.
        XCTAssertEqual(read(refusal(underDomain: NSPOSIXErrorDomain, code: 111)), .unreachable)
    }

    func testAClosedConnectionWithNoErrnoSaysUnreachableInsteadOfBlamingPermission() {
        XCTAssertEqual(read(URLError(.cannotConnectToHost)), .unreachable)
        XCTAssertEqual(read(URLError(.networkConnectionLost)), .unreachable)
    }

    func testAnErrorThatIsNotAURLFailureIsUnreachable() {
        struct NotAURLFailure: Error {}
        XCTAssertEqual(read(NotAURLFailure()), .unreachable)
    }

    // MARK: - What a status line means

    func testAStatusLineIsReadAsAFactAboutTheRow() {
        XCTAssertEqual(WebSearchFailure.response(status: 401), .providerUnavailable)
        XCTAssertEqual(WebSearchFailure.response(status: 403), .blocked)
        XCTAssertEqual(WebSearchFailure.response(status: 404), .invalidEndpoint)
        XCTAssertEqual(WebSearchFailure.response(status: 429), .rateLimited)
    }

    func testAServerOnFireIsUnreachableAndAnOddSuccessIsAShapeProblem() {
        XCTAssertEqual(WebSearchFailure.response(status: 500), .unreachable)
        XCTAssertEqual(WebSearchFailure.response(status: 503), .unreachable)
        XCTAssertEqual(WebSearchFailure.response(status: 302), .unrecognizedResponse)
        XCTAssertEqual(WebSearchFailure.response(status: 200), .unrecognizedResponse)
    }
}
