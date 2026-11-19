import Foundation
import XCTest
@testable import CairnChatDomain

/// Per-provider consent, and the app-wide acknowledgement it sits beside.
///
/// The distinction these tests protect: agreeing that Cairn may use the network for tools is not the same as
/// agreeing that a particular company receives the user's questions. A grant keyed to "search" in general
/// would let a query go to a provider the user never picked, which is the exact thing the badge and the
/// disclosure exist to prevent.
final class WebSearchConsentTests: XCTestCase {
    private var duckDuckGo: WebSearchProviderProfile { .builtIn }
    private var lanInstance: WebSearchProviderProfile {
        WebSearchProviderProfile(
            kind: .searxng, displayName: "Box", baseURLString: "http://192.168.1.20:8888"
        )
    }

    func testAFreshInstallHasConsentedToNothing() {
        XCTAssertEqual(WebSearchConsentState.default.decision(for: duckDuckGo), .undecided)
        XCTAssertTrue(WebSearchConsentState.default.requiresPrompt(for: duckDuckGo))
    }

    func testAGrantIsHeldAgainstTheProviderNotAgainstSearchInGeneral() {
        var consent = WebSearchConsentState.default
        consent.grant(duckDuckGo)
        XCTAssertEqual(consent.decision(for: duckDuckGo), .granted)
        XCTAssertFalse(consent.requiresPrompt(for: duckDuckGo))
        // A different instance is a different third party, even though "search" was already agreed to.
        let other = WebSearchProviderProfile(
            kind: .searxng, displayName: "Elsewhere", baseURLString: "https://other.example.com"
        )
        XCTAssertEqual(consent.decision(for: other), .undecided, "a new public provider still has to ask")
    }

    func testAnInstanceOnTheUsersOwnNetworkNeedsNoSecondAsking() {
        let consent = WebSearchConsentState.default
        XCTAssertEqual(
            consent.decision(for: lanInstance), .granted,
            "the outbound acknowledgement already covers a query that never leaves the house"
        )
        XCTAssertFalse(consent.requiresPrompt(for: lanInstance))
    }

    func testDecliningIsRememberedAndWithdrawingAGrantIsPossible() {
        var consent = WebSearchConsentState.default
        consent.deny(duckDuckGo)
        XCTAssertEqual(consent.decision(for: duckDuckGo), .denied)
        XCTAssertFalse(
            consent.requiresPrompt(for: duckDuckGo),
            "asking every turn until the user gives in is not consent"
        )
        consent.grant(duckDuckGo)
        XCTAssertEqual(consent.decision(for: duckDuckGo), .granted)
        consent.deny(duckDuckGo)
        XCTAssertEqual(consent.decision(for: duckDuckGo), .denied, "a refusal wins over an earlier grant")
    }

    func testRevokeOpensTheQuestionAgain() {
        var consent = WebSearchConsentState.default
        consent.grant(duckDuckGo)
        consent.revoke(providerID: duckDuckGo.id, kind: duckDuckGo.kind)
        XCTAssertEqual(consent.decision(for: duckDuckGo), .undecided)
    }

    func testConsentForADeletedProviderDoesNotOutliveIt() throws {
        var store = WebSearchProviderStore.default
        var consent = WebSearchConsentState.default
        let row = WebSearchProviderProfile(
            kind: .searxng, displayName: "Box", baseURLString: "https://search.example.com"
        )
        try store.add(row)
        consent.grant(row)
        consent.grant(duckDuckGo)
        try store.remove(id: row.id)
        consent.removingProviders(notIn: store)
        XCTAssertEqual(consent.grantedKeys.count, 1, "only the built-in row's grant is left")
        XCTAssertTrue(consent.grantedKeys.contains(WebSearchConsentState.key(
            providerID: duckDuckGo.id, kind: duckDuckGo.kind
        )))
    }

    /// Nothing here is a query or a secret, so the whole state is safe to persist — which is the point of
    /// holding it as keys rather than as a record of what was asked.
    func testTheConsentStateCarriesNoQueryTextAndRoundTrips() throws {
        var consent = WebSearchConsentState.default
        consent.grant(duckDuckGo)
        consent.deny(lanInstance)
        let blob = try JSONEncoder().encode(consent)
        let text = String(decoding: blob, as: UTF8.self)
        XCTAssertFalse(text.contains("what is the weather"), "a consent record is not a search log")
        let revived = try JSONDecoder().decode(WebSearchConsentState.self, from: blob)
        XCTAssertEqual(revived, consent)
    }
}
