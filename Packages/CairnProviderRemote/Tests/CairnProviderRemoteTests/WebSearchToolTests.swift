import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// `web_search`'s contract: one provider, only the query leaves, and every failure named.
///
/// Nothing here opens a socket. `RecordingWebTransport` answers with a canned reply and records the request
/// that *would* have gone out, which is the only way "only the query leaves" and "nothing was sent" can be
/// asserted rather than believed.
final class WebSearchToolTests: XCTestCase {
    private func call(_ query: String) -> ToolCall {
        ToolCall(id: "c1", name: BuiltInTool.webSearch, arguments: ["query": .text(query)])
    }

    private func context(allowed: Bool = true) -> ToolExecutionContext {
        ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: allowed)
    }

    private func tool(
        _ state: WebSearchState,
        reply: WebHTTPResponse = .json(
            #"{"results":[{"title":"Rain","url":"https://example.com/paris","snippet":"Wet."}]}"#
        ),
        throws error: (any Error)? = nil,
        throttle: WebSearchThrottle? = nil
    ) -> (WebSearchTool, RecordingWebTransport) {
        let transport = RecordingWebTransport(reply: reply, throws: error)
        let built = WebSearchTool(
            state: { state }, transport: transport, throttle: throttle ?? WebSearchThrottle()
        )
        return (built, transport)
    }

    // The failure assertion is the shared `expectSearchFailure` in `WebSearchTestDoubles`: one place, and a
    // catch list that closes over every error. A `do`/`catch` ending on `catch let thrown as ToolFailure` is
    // not exhaustive, and Swift only permits that in a function that itself throws — a plain `async` test
    // method gets a compile error instead of a second copy of the same shape.

    // MARK: one provider, no fallback

    func testTheActiveRowIsTheProviderAndNothingElseIsConsulted() throws {
        let lan = lanRow()
        XCTAssertTrue(WebSearchTool.provider(for: lan) is SearxngSearch)
        XCTAssertTrue(WebSearchTool.provider(for: .builtIn) is DuckDuckGoSearch)
        XCTAssertTrue(WebSearchTool.provider(for: cloudRow()) is OllamaCloudSearch)
    }

    func testAFailingProviderIsNotReplacedByAnotherOne() async {
        let (search, transport) = tool(
            searchState(lanRow()), reply: .json("{}", status: 429)
        )
        await expectSearchFailure(.rateLimited) {
            try await search.execute(self.call("rain in Paris"), context: self.context())
        }
        XCTAssertEqual(transport.requestCount, 1, "one provider, one request, no second attempt elsewhere")
        XCTAssertEqual(transport.requests.first?.url?.host, "192.168.1.20", "still the user's own box")
    }

    // MARK: only the query leaves

    func testOnlyTheQueryLeavesAndTheProviderIsNamedInTheAnswer() async throws {
        let (search, transport) = tool(searchState(lanRow(name: "Box")))
        let outcome = try await search.execute(call("rain in Paris"), context: context())
        XCTAssertTrue(outcome.succeeded, outcome.detail ?? "")

        XCTAssertEqual(transport.requestCount, 1)
        let sent = try XCTUnwrap(transport.requests.first)
        let items = RequestReader.queryItems(sent)
        XCTAssertEqual(items["q"], "rain in Paris")
        XCTAssertEqual(items["format"], "json")
        XCTAssertEqual(items["safesearch"], "1")
        XCTAssertNil(sent.httpBody, "a search GET carries no body to hide a transcript in")
        let wire = (sent.url?.absoluteString ?? "") + (RequestReader.header(sent, "User-Agent") ?? "")
        XCTAssertFalse(wire.contains("Lisbon"), "nothing from the conversation travels")

        XCTAssertTrue(outcome.modelText.contains("Box"), "the row is named")
        XCTAssertTrue(outcome.modelText.contains("https://example.com/paris"))
        XCTAssertFalse(outcome.modelText.contains("Lisbon"))
    }

    func testTheBuiltInRowNamesDuckDuckGoAndSaysCairnIsNotAffiliatedWithIt() async throws {
        let page = #"<a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fparis&rut=x">Rain in Paris</a><div class="result__snippet">A wet city.</div>"#
        let (search, _) = tool(searchState(), reply: .html(page))
        let outcome = try await search.execute(call("rain in Paris"), context: context())
        XCTAssertTrue(outcome.modelText.contains("DuckDuckGo"), "the third party is named out loud")
        XCTAssertTrue(outcome.modelText.contains("not affiliated"), "and the relationship is stated")
        XCTAssertTrue(outcome.modelText.contains("https://example.com/paris"), "the redirector is unwrapped")
        XCTAssertTrue(outcome.modelText.contains("A wet city."), "the snippet is the provider's own words")
    }

    func testSponsoredLinksAreNotHandedToTheModelAsSources() async throws {
        let page = #"<div class="result--ad"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fpaid.example.com">Buy umbrellas</a></div><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fparis">Rain</a><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fparis">Rain again</a>"#
        let (search, _) = tool(searchState(), reply: .html(page))
        let outcome = try await search.execute(call("rain in Paris"), context: context())
        XCTAssertFalse(outcome.modelText.contains("paid.example.com"), "a bought link is not a source")
        XCTAssertTrue(outcome.modelText.contains("example.com/paris"))
        XCTAssertEqual(
            outcome.modelText.components(separatedBy: "example.com/paris").count - 1,
            1,
            "the same address twice is one source, not two"
        )
    }

    // MARK: consent, before the socket

    func testAnUndecidedProviderSendsNothingAndSaysItHasToAsk() async {
        var state = searchState(consent: .denied)
        state.settings.consent.revoke(providerID: state.provider.id, kind: state.provider.kind)
        let (search, transport) = tool(state)
        await expectSearchFailure(.internetNotAllowed) {
            try await search.execute(self.call("rain in Paris"), context: self.context())
        }
        XCTAssertEqual(transport.requestCount, 0, "refused before the socket")
    }

    func testADeniedProviderIsRefusedWithoutAskingAgain() async {
        let (search, transport) = tool(searchState(consent: .denied))
        await expectSearchFailure(.internetNotAllowed) {
            try await search.execute(self.call("rain in Paris"), context: self.context())
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testNoQueryLeavesWhenTheOutboundAcknowledgementIsDown() async {
        let (search, transport) = tool(searchState())
        let registry = ToolRegistry(tools: [search])
        let outcome = await registry.execute(call("rain in Paris"), context: context(allowed: false))
        XCTAssertEqual(outcome.error, .internetNotAllowed)
        XCTAssertEqual(transport.requestCount, 0, "refused before the socket")
        XCTAssertFalse(
            registry.availableDefinitions(context: context(allowed: false))
                .contains { $0.name == BuiltInTool.webSearch },
            "not offered, not just refused"
        )
        XCTAssertTrue(
            registry.availableDefinitions(context: context())
                .contains { $0.name == BuiltInTool.webSearch }
        )
    }

    // MARK: the distinction the taxonomy exists for

    func testAChangedPageIsAFailureAndNeverAnEmptyAnswer() async {
        let (search, _) = tool(searchState(), reply: .html("<html>the page changed</html>"))
        do {
            _ = try await search.execute(call("rain in Paris"), context: context())
            XCTFail("a page with no result markers is not a result")
        } catch let thrown as ToolFailure {
            XCTAssertEqual(thrown.error, .endpointMalformed)
            XCTAssertTrue(
                (thrown.detail ?? "").contains("not a report of nothing being found"),
                "the model must be told the provider broke, not that nothing exists"
            )
        } catch {
            XCTFail("expected a typed failure, threw \(type(of: error))")
        }
    }

    func testAnEmptyAnswerIsASuccessThatSaysSoRatherThanAFailure() async throws {
        let (search, _) = tool(searchState(lanRow()), reply: .json(#"{"results":[]}"#))
        let outcome = try await search.execute(call("qqxxzz"), context: context())
        XCTAssertTrue(outcome.succeeded, "nothing found is information, not a broken tool")
        XCTAssertTrue(outcome.modelText.contains("returned nothing"))
        XCTAssertTrue(outcome.modelText.contains("Box"), "and it says who found nothing")
    }
}
