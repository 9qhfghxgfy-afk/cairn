import Foundation
import XCTest
@testable import CairnChatDomain

/// The badge's rule, as a value rather than as a view.
///
/// The rule replaced a receipt. It used to be "a turn used a tool, so show that one did" — the last moment a
/// notice can be read, because the query had already left. Now it is "this is the standing condition: the
/// tools are on and the provider you selected is beyond your own network", which is true before the first
/// request and is therefore worth showing. Both halves are load-bearing, so both are tested.
final class WebSearchBadgeRuleTests: XCTestCase {

    private var lanRow: WebSearchProviderProfile {
        WebSearchProviderProfile(
            kind: .searxng, displayName: "Box", baseURLString: "http://192.168.1.20:8888"
        )
    }

    private var publicRow: WebSearchProviderProfile {
        WebSearchProviderProfile(
            kind: .searxng, displayName: "Remote", baseURLString: "https://search.example.com"
        )
    }

    func testAPublicProviderWithToolsOnShowsBeforeAnythingIsSent() {
        XCTAssertTrue(
            WebSearchBadgeRule.showsImmediately(profile: publicRow, webToolsEnabled: true),
            "the whole point is that it is up before the query goes"
        )
    }

    func testToolsOffShowsNothingHoweverPublicTheProviderIs() {
        XCTAssertFalse(
            WebSearchBadgeRule.showsImmediately(profile: .builtIn, webToolsEnabled: false),
            "a provider nobody can reach is not a disclosure"
        )
    }

    func testAProviderOnTheUsersOwnNetworkIsNotAnOutboundBadge() {
        XCTAssertFalse(
            WebSearchBadgeRule.showsImmediately(profile: lanRow, webToolsEnabled: true),
            "traffic that stays inside the user's own network must not be flagged as leaving it"
        )
    }

    /// The built-in row is a third party, and the badge has to say which one — "a tool sent something" is not
    /// a fact a person can act on, while "search goes to DuckDuckGo" is.
    func testTheLineNamesWhereQueriesGoRatherThanWhichToolRan() {
        XCTAssertEqual(WebSearchBadgeRule.detail(profile: .builtIn), "Search goes to DuckDuckGo")
        XCTAssertEqual(WebSearchBadgeRule.detail(profile: publicRow), "Search goes to Remote")
    }

    /// The payload is what the sheet says is leaving: a search's words, or one page address. A sheet that said
    /// "something may go out" for both tools would be worth nothing, so the two stay distinguishable.
    func testThePayloadDistinguishesTheUsersWordsFromAnAddress() {
        XCTAssertTrue(WebConsentPayload.searchQuery.isQuery)
        XCTAssertFalse(WebConsentPayload.fetchTarget(host: "example.com").isQuery)
    }

    /// The settings value already answers the public question, and the rule must agree with it — a badge and a
    /// screen that disagree about whether traffic leaves is the failure this file is here to prevent.
    func testTheRuleAgreesWithTheSettingsValue() {
        var search = WebSearchSettings.default
        XCTAssertTrue(search.activeProviderReachesPublicInternet)
        try? search.providers.add(lanRow)
        XCTAssertFalse(search.providers.active.reachesPublicInternet)
        XCTAssertEqual(
            WebSearchBadgeRule.showsImmediately(
                profile: search.activeProvider, webToolsEnabled: true
            ),
            search.activeProviderReachesPublicInternet
        )
    }
}
