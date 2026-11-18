import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// P3b search: which endpoint one query goes to, and what travels with it.
///
/// Everything here is asserted on the request that was built, because that is the only place the
/// privacy claim can be checked: a search tool must send the query and nothing else — no transcript,
/// no profile name, and no key except the one the chosen endpoint needs. The route that ran is named
/// in the answer, so a fallback to a public service is never hidden inside a tool.
@MainActor
final class WebSearchToolTests: XCTestCase {

    private let transcript = "Note from the chat: the Lisbon trip is off."

    private func call(_ query: String) -> ToolCall {
        ToolCall(id: "call-1", name: BuiltInTool.webSearch, arguments: ["query": .text(query)])
    }

    private func context(allowed: Bool = true, limit: Int = 5) -> ToolExecutionContext {
        ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: allowed, searchResultLimit: limit)
    }

    private func tool(_ state: WebSearchState, reply: WebHTTPResponse = .json(#"{"results":[]}"#)) -> WebSearchTool {
        WebSearchTool(state: { state }, transport: RecordingWebTransport(reply: reply))
    }

    /// The order the routes take, and the reason for it: the server this chat already talks to goes
    /// first, a self-hosted instance removes the third party entirely, and the keyless default is the
    /// last resort rather than a failure when a cloud profile has no key.
    func testTheRouteOrderIsCloudWithAKeyThenOwnInstanceThenKeyless() {
        XCTAssertEqual(
            WebSearchTool.provider(for: searchState(searxng: "http://192.168.1.20:8888", serverKind: .ollamaCloud, cloudToken: "k")).route,
            .ollamaCloud, "a key on the server in use beats a configured instance"
        )
        XCTAssertEqual(
            WebSearchTool.provider(for: searchState(searxng: "http://192.168.1.20:8888", serverKind: .ollamaCloud)).route,
            .searxng, "a cloud profile with no key falls through, and says so"
        )
        XCTAssertEqual(
            WebSearchTool.provider(for: searchState(searxng: "https://search.example.com", serverKind: .ollama)).route,
            .searxng, "the user's own instance beats the built-in default"
        )
        XCTAssertEqual(WebSearchTool.provider(for: searchState()).route, .keyless)
    }

    /// Each route builds its own request, and the only field in it is the query (plus the count the
    /// cloud endpoint asks for). A key travels to the endpoint that issued it and nowhere else.
    func testEachRouteSendsTheQueryAndNothingElse() throws {
        let cloud = try XCTUnwrap(WebSearchTool.provider(for: searchState(serverKind: .ollamaCloud, cloudToken: "tok")).request(for: "rain in Paris", limit: 3))
        XCTAssertEqual(cloud.url?.absoluteString, "https://ollama.com/api/web_search")
        XCTAssertEqual(cloud.httpMethod, "POST")
        XCTAssertEqual(RequestReader.header(cloud, "Authorization"), "Bearer tok")
        let fields = try RequestReader.bodyFields(cloud)
        XCTAssertEqual(Set(fields.keys), ["query", "max_results"], "two keys and nothing else")
        XCTAssertEqual(fields["query"] as? String, "rain in Paris")
        XCTAssertEqual(fields["max_results"] as? Int, 3)

        let own = try XCTUnwrap(WebSearchTool.provider(for: searchState(searxng: "http://192.168.1.20:8888")).request(for: "rain in Paris", limit: 3))
        XCTAssertEqual(own.url?.host, "192.168.1.20", "the user's own instance, over plain http")
        XCTAssertEqual(own.url?.path, "/search")
        XCTAssertEqual(RequestReader.queryItems(own), ["format": "json", "q": "rain in Paris"])
        XCTAssertNil(RequestReader.header(own, "Authorization"), "no key travels to a self-hosted box")

        let free = try XCTUnwrap(WebSearchTool.provider(for: searchState()).request(for: "rain in Paris", limit: 3))
        XCTAssertEqual(free.url?.host, "html.duckduckgo.com")
        XCTAssertEqual(RequestReader.queryItems(free), ["q": "rain in Paris"], "one parameter")
        XCTAssertNil(RequestReader.header(free, "Authorization"))
    }
    /// One query out, a named route back. The request carries one parameter and no body, and the
    /// planted conversation word appears nowhere on the wire: the endpoint has no business knowing
    /// anything about this conversation beyond the words it is being asked about.
    func testOnlyTheQueryLeavesAndTheRouteIsNamedInTheAnswer() async throws {
        let state = searchState(searxng: "http://192.168.1.20:8888")
        let transport = RecordingWebTransport(
            reply: .json(#"{"results":[{"title":"Rain","url":"https://example.com/paris","snippet":"Wet."}]}"#)
        )
        let outcome = try await WebSearchTool(state: { state }, transport: transport)
            .execute(call("rain in Paris"), context: context())
        XCTAssertTrue(outcome.succeeded, outcome.detail ?? "")

        XCTAssertEqual(transport.requestCount, 1, "one request for one query")
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(RequestReader.queryItems(sent), ["format": "json", "q": "rain in Paris"])
        XCTAssertNil(sent.httpBody, "a search GET carries no body to hide a transcript in")
        let wire = (sent.url?.absoluteString ?? "") + (RequestReader.header(sent, "User-Agent") ?? "")
        XCTAssertFalse(wire.contains("Lisbon"), "nothing from the conversation travels")

        XCTAssertTrue(outcome.modelText.contains("Searched your own SearXNG instance."), "the route is named")
        XCTAssertTrue(outcome.modelText.contains("https://example.com/paris"), "the URL is handed back to fetch")
        XCTAssertFalse(outcome.modelText.contains("Lisbon"))
    }

    /// The keyless route answers with a page, not an API, so its markers are best-effort. When they
    /// move, the honest answer is no results — a typed failure the model can see, never a page of
    /// markup dressed up as sources or a guess at what the page meant.
    func testTheKeylessRouteUnwrapsItsRedirectorAndRefusesToInventResults() async throws {
        let page = #"<a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fparis&rut=x">Rain in Paris</a><div class="result__snippet">A wet city.</div>"#
        let found = try await WebSearchTool(state: { searchState() }, transport: RecordingWebTransport(reply: .html(page)))
            .execute(call("rain in Paris"), context: context())
        XCTAssertTrue(found.modelText.contains("https://example.com/paris"), "the redirector is unwrapped")
        XCTAssertTrue(found.modelText.contains("A wet city."), "the snippet is the endpoint's own words")
        XCTAssertTrue(found.modelText.contains("built-in keyless endpoint"), "the third party is named out loud")

        do {
            _ = try await WebSearchTool(state: { searchState() }, transport: RecordingWebTransport(reply: .html("<html>the page changed</html>")))
                .execute(call("rain in Paris"), context: context())
            XCTFail("a page with no result markers is not a result")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.error, .searchUnavailable)
        }
    }

    /// The acknowledgement is a separate switch from the chat's `Tools` chip. With the chip up and the
    /// acknowledgement down, the registry refuses the call and not one byte leaves the device — and a
    /// tool it would refuse is never advertised to the model in the first place.
    func testNoQueryLeavesWhenTheOutboundAcknowledgementIsDown() async {
        let transport = RecordingWebTransport()
        let registry = ToolRegistry(tools: [WebSearchTool(state: { searchState() }, transport: transport)])
        let outcome = await registry.execute(call("rain in Paris"), context: context(allowed: false))
        XCTAssertEqual(outcome.error, .internetNotAllowed)
        XCTAssertEqual(transport.requestCount, 0, "refused before the socket")
        let offered = registry.availableDefinitions(context: context(allowed: false))
        XCTAssertFalse(offered.contains { $0.name == BuiltInTool.webSearch }, "not offered, not just refused")
        XCTAssertTrue(registry.availableDefinitions(context: context()).contains { $0.name == BuiltInTool.webSearch })
    }
}
