import Foundation
import XCTest
@testable import CairnChatDomain

/// The failure taxonomy: what each failure says, and what it makes the loop do next.
///
/// The case worth defending is `unrecognizedResponse`. It exists because a provider whose output format
/// moved used to look like "no results", and a model that reports "nothing was found" when the search
/// actually broke has told the user something false with a straight face. These tests keep that distinction
/// from collapsing back into an empty list.
final class WebSearchFailureTests: XCTestCase {
    func testEveryFailureNamesItsReasonAndCarriesNoAddressOrBody() {
        for failure in WebSearchFailure.allCases {
            XCTAssertFalse(failure.userText.isEmpty)
            XCTAssertFalse(failure.modelReason.isEmpty)
            for forbidden in ["http://", "https://", "<", "{", "\""] {
                XCTAssertFalse(
                    failure.userText.contains(forbidden),
                    "a card line must not carry a URL or a document: \(failure.rawValue)"
                )
                XCTAssertFalse(
                    failure.modelReason.contains(forbidden),
                    "the model's line is logged metadata's neighbour; keep it prose: \(failure.rawValue)"
                )
            }
        }
    }

    func testTheProviderIsNamedToTheModelBecauseWhichOneFailedIsTheFact() {
        XCTAssertTrue(
            WebSearchFailure.unreachable.modelText(providerName: "Box")
                .contains("Web search via Box did not run")
        )
        XCTAssertTrue(
            WebSearchFailure.blocked.modelText(providerName: "DuckDuckGo").contains("DuckDuckGo")
        )
    }

    func testAChangedResponseIsNeverReportedAsAnAbsentResult() {
        XCTAssertEqual(WebSearchFailure.unrecognizedResponse.toolError, .endpointMalformed)
        XCTAssertEqual(WebSearchFailure.decodeFailed.toolError, .endpointMalformed)
        XCTAssertNotEqual(WebSearchFailure.unrecognizedResponse.toolError, .searchUnavailable)
        XCTAssertTrue(
            WebSearchFailure.unrecognizedResponse.modelReason.contains("not a report of nothing being found")
        )
    }

    /// A rate limit or a refusal will not answer a better query. Letting the loop spend its remaining steps
    /// discovering that costs the user context and gets the same answer.
    func testFailuresTheModelCannotFixAreNotRetried() {
        for failure in [WebSearchFailure.blocked, .rateLimited, .unrecognizedResponse, .decodeFailed,
                        .enginesUnavailable, .providerUnavailable, .httpsRequired,
                        .localNetworkDenied, .permissionDenied] {
            XCTAssertFalse(
                failure.toolError.modelCanRetry,
                "\(failure.rawValue) is not something a different query fixes"
            )
        }
        XCTAssertTrue(WebSearchFailure.unreachable.toolError.modelCanRetry)
        XCTAssertTrue(WebSearchFailure.timedOut.toolError.modelCanRetry)
    }

    func testConfigurationProblemsAreTheOnesThatPointAtSettings() {
        for failure in [WebSearchFailure.httpsRequired, .invalidEndpoint, .providerUnavailable,
                        .localNetworkDenied, .permissionDenied] {
            XCTAssertTrue(failure.isConfigurationProblem, "\(failure.rawValue) is fixed in Settings")
        }
        for failure in [WebSearchFailure.blocked, .rateLimited, .unrecognizedResponse, .decodeFailed,
                        .enginesUnavailable, .unreachable, .timedOut] {
            XCTAssertFalse(failure.isConfigurationProblem, "\(failure.rawValue) is not a setting")
        }
    }

    func testARefusedConsentReadsAsTheOptInItIs() {
        XCTAssertEqual(WebSearchFailure.permissionDenied.toolError, .internetNotAllowed)
        XCTAssertTrue(
            WebSearchFailure.permissionDenied.modelReason.contains("Do not retry"),
            "the model must not spend the turn asking again"
        )
    }

    func testTheTaxonomyRoundTripsAndCoversEveryCaseOnce() throws {
        let blob = try JSONEncoder().encode(WebSearchFailure.allCases)
        let revived = try JSONDecoder().decode([WebSearchFailure].self, from: blob)
        XCTAssertEqual(revived, WebSearchFailure.allCases)
        XCTAssertEqual(Set(WebSearchFailure.allCases.map(\.rawValue)).count, WebSearchFailure.allCases.count)
    }
}
