import Foundation
import CairnChatDomain

/// `wiki_search`: the Wikipedia Action API's search, with the excerpt each result published.
///
/// One request, one bounded answer, and no scraping: `action=query&list=search` is the documented
/// search surface, and the `snippet` it returns is Wikipedia's own text, stripped of markup rather than
/// rewritten. A page's URL is built from its title because the API names the title and the URL scheme
/// is public — so the model can hand that URL straight to `web_fetch` for the full article.
public struct WikiSearchTool: ToolExecuting {
    static let endpointURL = "https://en.wikipedia.org/w/api.php"
    static let articleBase = "https://en.wikipedia.org/wiki/"

    private let transport: any WebRequesting
    private let byteLimit: Int

    public init(
        transport: any WebRequesting = WebHTTPTransport(),
        byteLimit: Int = 128_000
    ) {
        self.transport = transport
        self.byteLimit = byteLimit
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.wikiSearch,
            blurb: """
                Look a topic up on Wikipedia and get its title, URL and published excerpt back. \
                Use it for encyclopaedic background; for anything current or disputed, use web_search \
                as well. The excerpt is what Wikipedia wrote, not a summary of the whole article — \
                fetch the URL with web_fetch when the article itself is what you need.
                """,
            parameters: ToolParameterSchema(
                properties: [
                    "query": ToolParameter(
                        kind: .string,
                        description: "The topic to look up, as a title or a short phrase."
                    ),
                ],
                required: ["query"]
            ),
            networkClass: .publicInternet
        )
    }

    public func execute(
        _ call: ToolCall, context: ToolExecutionContext
    ) async throws -> ToolOutcome {
        let query = WebSearchParsing.clean(call.arguments["query"]?.coercedText ?? "")
        guard !query.isEmpty else {
            throw ToolFailure(.badArguments, detail: "Give a topic in the \"query\" argument.")
        }
        guard let request = Self.request(for: query, limit: context.searchResultLimit) else {
            throw ToolFailure(.searchUnavailable, detail: "The Wikipedia search endpoint could not be addressed.")
        }
        let response = try await transport.send(
            request, byteLimit: byteLimit, redirectAllowed: WebFetchGuard.allowsPublicHTTPS
        )
        guard response.succeeded else {
            throw ToolFailure(.failed, detail: "Wikipedia replied HTTP \(response.status).")
        }
        let rendered = WebSearchResult.render(Self.results(in: response, limit: context.searchResultLimit))
        guard !rendered.isEmpty else {
            throw ToolFailure(.searchUnavailable, detail: "Wikipedia has no article matching that topic.")
        }
        return .success(
            callID: call.id, toolName: call.name,
            output: "Searched Wikipedia; the query went to the public Wikipedia API.\n\n\(rendered)"
        )
    }

    /// The documented search call. `srnamespace=0` keeps it in articles, so a result is a page a reader
    /// could open rather than an editor's discussion about one.
    static func request(for query: String, limit: Int) -> URLRequest? {
        guard var components = URLComponents(string: endpointURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srnamespace", value: "0"),
            URLQueryItem(name: "srlimit", value: String(min(max(1, limit), 10))),
            URLQueryItem(name: "srinfo", value: "snippet"),
        ]
        guard let url = components.url else { return nil }
        return WebFetchGuard.request(for: url, accept: "application/json")
    }
}
