import XCTest
import CairnChatDomain
import CairnAppUI
import CairnProviderRemote

/// The app-layer web seams, run end to end on the simulator.
///
/// These exist because the consent decision is split across three modules by design: the domain holds the
/// record, the UI holds the sheet, and only the app layer is allowed to join them. A unit test in any one of
/// them would pass with the join missing — which is precisely the bug: a tool that runs without ever asking.
/// So each test drives the seam the tool actually calls and checks both the answer and the record it left.
@MainActor
final class WebSearchConsentWiringTests: XCTestCase {

    private var acknowledged: AppSettings {
        var settings = AppSettings.default
        settings.setOutboundWebAllowed(true)
        return settings
    }

    private func makeWiring(_ settings: AppSettings = AppSettings.default) -> WebSearchWiring {
        WebSearchWiring.install(
            theme: ThemeModel(settings: settings),
            serverSecrets: MemorySecretStore(),
            searchSecrets: MemorySecretStore(),
            testing: nil
        )
    }

    /// Waits until a question is genuinely on the sheet, instead of assuming a slice of main-actor time.
    ///
    /// The seam parks the asking side on a continuation, and an `async let` only reaches it when this task
    /// yields. A fixed sleep is a guess about how long that takes: a loaded CI runner can stall past any
    /// constant, and a test that then answers a question that was never asked would sit waiting forever for a
    /// reply nobody gave — a hang rather than a failure. Yielding until the condition holds turns the wait into
    /// a condition, and the deadline makes a broken join report itself instead of running to the job timeout.
    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { return false }
            await Task.yield()
        }
        return true
    }

    func testAPublicSearchStopsAndAsksBeforeASingleByteLeaves() async {
        let wiring = makeWiring(acknowledged)
        let profile = ThemeModel(settings: acknowledged).settings.webSearch.activeProvider
        async let answer = wiring.searchRequester(profile)
        let asked = await waitUntil { wiring.consent.pending != nil }
        XCTAssertTrue(asked, "the request must be parked on a sheet, not in flight")
        XCTAssertTrue(wiring.consent.pending?.isSearch ?? false, "a provider question, not a page one")
        wiring.consent.resolve(allow: true)

        let allowed = await answer
        XCTAssertTrue(allowed)
        XCTAssertNil(wiring.consent.pending, "the sheet is gone once it is answered")
    }

    func testAnAnswerIsFiledAgainstThatProviderAndStopsTheAsking() async {
        let theme = ThemeModel(settings: acknowledged)
        let wiring = makeWiring(theme.settings)
        let profile = theme.settings.webSearch.activeProvider
        async let answer = wiring.searchRequester(profile)
        let asked = await waitUntil { wiring.consent.pending != nil }
        XCTAssertTrue(asked, "the row has to be on the sheet before an answer can be filed against it")
        wiring.consent.resolve(allow: true)
        let granted = await answer
        XCTAssertTrue(granted, "the sheet's yes is the answer the tool gets")

        XCTAssertEqual(theme.settings.webSearch.consentDecision(for: profile), .granted)
        let second = await wiring.searchRequester(profile)
        XCTAssertTrue(second)
        XCTAssertNil(wiring.consent.pending, "a granted provider does not interrupt twice")
    }

    func testADenialIsHeldAndTheToolRefusesWithoutAskingAgain() async {
        let theme = ThemeModel(settings: acknowledged)
        let wiring = makeWiring(theme.settings)
        let profile = theme.settings.webSearch.activeProvider
        async let answer = wiring.searchRequester(profile)
        let asked = await waitUntil { wiring.consent.pending != nil }
        XCTAssertTrue(asked, "a refusal is still an answer that has to be given")
        wiring.consent.resolve(allow: false)

        let allowed = await answer
        XCTAssertFalse(allowed, "a seam that lost the refusal would let the query out")
        XCTAssertEqual(theme.settings.webSearch.consentDecision(for: profile), .denied)
        let askedAgain = await wiring.searchRequester(profile)
        XCTAssertFalse(askedAgain, "a stored no is an answer, not a fresh question")
        XCTAssertNil(wiring.consent.pending)
    }

    /// Dismissing a sheet is not silence: it is the answer "no", held the same way an explicit refusal is. A
    /// walk-away that left the record blank would ask again on the next turn, and one that let the continuation
    /// dangle would hang the tool forever.
    func testWalkingAwayFromTheSheetCountsAsANoAndDoesNotHang() async {
        let theme = ThemeModel(settings: acknowledged)
        let wiring = makeWiring(theme.settings)
        let profile = theme.settings.webSearch.activeProvider
        async let answer = wiring.searchRequester(profile)
        let asked = await waitUntil { wiring.consent.pending != nil }
        XCTAssertTrue(asked, "walking away only means something if there was a sheet to walk away from")
        wiring.consent.declineUnanswered()

        let allowed = await answer
        XCTAssertFalse(allowed)
        XCTAssertEqual(theme.settings.webSearch.consentDecision(for: profile), .denied)
    }

    /// One sheet at a time, so two turns that both want to ask cannot stack two sheets on each other.
    func testTwoQuestionsQueueInsteadOfStacking() async throws {
        var search = WebSearchSettings.default
        try search.providers.add(WebSearchProviderProfile(
            kind: .searxng, displayName: "First", baseURLString: "https://one.example.com"
        ))
        try search.providers.add(WebSearchProviderProfile(
            kind: .searxng, displayName: "Second", baseURLString: "https://two.example.com"
        ))
        var settings = acknowledged
        settings.setWebSearch(search)
        let theme = ThemeModel(settings: settings)
        let wiring = makeWiring(theme.settings)
        let rows = theme.settings.webSearch.allProviders.filter { $0.reachesPublicInternet }
        XCTAssertEqual(rows.count, 3, "both added rows and the built-in one are third parties")

        async let first = wiring.searchRequester(rows[0])
        async let second = wiring.searchRequester(rows[1])
        let firstWasAsked = await waitUntil {
            wiring.consent.pending?.profile?.displayName == rows[0].displayName
        }
        XCTAssertTrue(firstWasAsked, "one at a time, and the first one first")

        wiring.consent.resolve(allow: true)
        let secondWasAsked = await waitUntil {
            wiring.consent.pending?.profile?.displayName == rows[1].displayName
        }
        XCTAssertTrue(secondWasAsked, "the next question takes the sheet's turn instead of stacking on it")
        wiring.consent.resolve(allow: true)

        let answers = [await first, await second]
        XCTAssertEqual(answers, [true, true])
        XCTAssertNil(wiring.consent.pending)
    }


    func testAPageReadIsOneAnswerForTheToolRatherThanOnePerHost() async {
        let theme = ThemeModel(settings: acknowledged)
        let wiring = makeWiring(theme.settings)
        async let answer = wiring.fetchRequester(URL(string: "https://example.com/a")!)
        let asked = await waitUntil { wiring.consent.pending != nil }
        XCTAssertTrue(asked, "a page read has to stop and ask before it reads")
        XCTAssertFalse(wiring.consent.pending?.isSearch ?? true, "a page, not a provider")
        wiring.consent.resolve(allow: true)
        let read = await answer
        XCTAssertTrue(read)
        XCTAssertEqual(theme.settings.webFetchAllowed, true)

        let otherHost = await wiring.fetchRequester(URL(string: "https://elsewhere.example.org")!)
        XCTAssertTrue(otherHost, "the answer was to the tool, so a second host does not re-ask")
        XCTAssertNil(wiring.consent.pending)
    }
}

