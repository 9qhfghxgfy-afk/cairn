import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// P3b wiki search: the documented Action API call, and the excerpt as Wikipedia wrote it.
///
/// The request is asserted field by field because the parameter set is published, and the excerpt is
/// asserted as text with no markup in it because the model reads it as the article's own words. A
/// search-highlighting tag left in the snippet would be markup arriving as though it were prose.
@MainActor
final class WikiSearchToolTests: XCTestCase {

    private func call(_ topic: String) -> ToolCall {
        ToolCall(id: "call-1", name: BuiltInTool.wikiSearch, arguments: ["query": .text(topic)])
    }

    /// The documented search surface: articles only, JSON out, the published snippet, and a bounded
    /// count whatever the turn asked for. Nothing else travels.
    func testAWikiSearchSendsOnlyTheDocumentedParameters() throws {
        let request = try XCTUnwrap(WikiSearchTool.request(for: "Great Barrier Reef", limit: 25))
        XCTAssertEqual(request.url?.host, "en.wikipedia.org")
        XCTAssertEqual(request.url?.path, "/w/api.php")
        let items = RequestReader.queryItems(request)
        XCTAssertEqual(
            Set(items.keys),
            ["action", "format", "list", "srsearch", "srnamespace", "srlimit", "srinfo"],
            "the published set and nothing else"
        )
        XCTAssertEqual(items["action"], "query")
        XCTAssertEqual(items["format"], "json")
        XCTAssertEqual(items["list"], "search")
        XCTAssertEqual(items["srsearch"], "Great Barrier Reef")
        XCTAssertEqual(items["srnamespace"], "0", "a reader could open the result, not discuss it")
        XCTAssertEqual(items["srlimit"], "10", "bounded, however many were asked for")
        XCTAssertEqual(items["srinfo"], "snippet")
        XCTAssertNil(RequestReader.header(request, "Authorization"))
        XCTAssertNil(RequestReader.header(request, "Cookie"))
    }

    /// A JSON document as one endpoint would answer it, built by the serialiser. Hand-quoting a fixture
    /// that carries quoted markup inside a JSON string is how a test goes wrong in its own fixture
    /// rather than in the parser under test.
    private func jsonPayload(_ payload: [String: Any]) throws -> WebHTTPResponse {
        WebHTTPResponse(
            status: 200, data: try XCTUnwrap(JSONSerialization.data(withJSONObject: payload)),
            mimeType: "application/json", finalURL: nil
        )
    }

    /// Highlighting tags and entities are unwrapped, the article address is built from the title the
    /// API named, and a result with no excerpt keeps its emptiness rather than gaining a summary.
    func testAnExcerptArrivesAsProseWithItsAddressAndNoInventedSummary() throws {
        let markup = #"The <span class="searchmatch">reef</span> is &mdash; long &amp;   wide."#
        let results = WikiSearchTool.results(
            in: try jsonPayload([
                "query": ["search": [
                    ["title": "Great Barrier Reef", "snippet": markup],
                    ["title": "Bare Title"],
                ]],
            ]),
            limit: 5
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Great Barrier Reef")
        XCTAssertEqual(results[0].url, "https://en.wikipedia.org/wiki/Great%20Barrier%20Reef")
        XCTAssertFalse(results[0].snippet.contains("<span"), "no markup reaches the model")
        XCTAssertFalse(results[0].snippet.contains("searchmatch"))
        XCTAssertTrue(results[0].snippet.contains("The reef is"))
        XCTAssertTrue(results[0].snippet.contains("—"), "the entity is the character Wikipedia wrote")
        XCTAssertTrue(results[0].snippet.contains("long &"), "an ampersand is kept, not rewritten")
        XCTAssertFalse(results[0].snippet.contains("\n"), "one excerpt is one line, however the markup broke")
        XCTAssertEqual(
            results[0].snippet, results[0].snippet.trimmingCharacters(in: .whitespacesAndNewlines),
            "the excerpt starts and ends at the text, and the words stay Wikipedia's"
        )
        XCTAssertTrue(results[1].snippet.isEmpty, "nothing is said about a page that said nothing")
        XCTAssertEqual(WikiSearchTool.results(in: .json(#"{"query":{"search":[]}}"#), limit: 5).count, 0)
    }

    /// The route is named to the model, and an empty or refused answer is a typed failure rather than
    /// an invented article.
    func testAWikiSearchNamesItsRouteAndRefusesToInventAnArticle() async throws {
        let found = try await WikiSearchTool(transport: RecordingWebTransport(reply: .json(
            #"{"query":{"search":[{"title":"Reef","snippet":"A reef."}]}}"#
        ))).execute(call("reef"), context: ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true))
        XCTAssertTrue(found.modelText.contains("Searched Wikipedia"), "the query went to a named public API")
        XCTAssertTrue(found.modelText.contains("https://en.wikipedia.org/wiki/Reef"))

        let empty = RecordingWebTransport(reply: .json(#"{"query":{"search":[]}}"#))
        do {
            _ = try await WikiSearchTool(transport: empty).execute(call("reef"), context: ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true))
            XCTFail("no article matched, so nothing may be reported as one")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.error, .searchUnavailable)
        }
        XCTAssertEqual(empty.requestCount, 1, "the request was made and answered honestly")

        do {
            _ = try await WikiSearchTool(transport: RecordingWebTransport()).execute(call("  "), context: ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true))
            XCTFail("an empty topic is a bad argument, not a search")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.error, .badArguments)
        }
    }
}
