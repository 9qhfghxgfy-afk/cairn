import Foundation
import CairnChatDomain

/// `web_search`: one query out, a numbered result list back.
///
/// Two rules hold this tool honest, and they are the reason it is written the way it is:
///
/// - **Only the query leaves.** Every provider builds its request from the `query` argument alone — no
///   transcript, no attachment, no profile name, no token except the one the chosen endpoint needs.
///   `WebSearchToolTests` asserts that on the built request rather than trusting this sentence.
/// - **The route is named in the answer.** Whether a query went to the user's own SearXNG box, to the
///   cloud server this chat is already using, or to a public keyless service is a fact the model can
///   repeat and the user can check. A search that does not say where it looked is a disclosure hidden
///   inside a tool.
public struct WebSearchTool: ToolExecuting {
    private let state: WebSearchStateReader
    private let transport: any WebRequesting
    private let byteLimit: Int

    public init(
        state: @escaping WebSearchStateReader,
        transport: any WebRequesting = WebHTTPTransport(),
        byteLimit: Int = 64_000
    ) {
        self.state = state
        self.transport = transport
        self.byteLimit = byteLimit
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.webSearch,
            blurb: """
                Search the web with one short query and get numbered results back, each with its URL \
                and a snippet the search endpoint itself wrote. Only the query is sent; nothing from \
                this conversation goes with it. Use it when the answer is not already here, and name \
                which result you used. A result you did not read tells you nothing — pass its URL to \
                web_fetch if you need its contents.
                """,
            parameters: ToolParameterSchema(
                properties: [
                    "query": ToolParameter(
                        kind: .string,
                        description: "The search query, phrased as the words you would type."
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
            throw ToolFailure(.badArguments, detail: "Give a search query in the \"query\" argument.")
        }
        let current = await state()
        let provider = Self.provider(for: current)
        guard let request = provider.request(for: query, limit: context.searchResultLimit) else {
            throw ToolFailure(
                .searchUnavailable,
                detail: "The configured search address could not be used. Check it in Settings."
            )
        }
        let response = try await transport.send(
            request, byteLimit: byteLimit, redirectAllowed: provider.redirectAllowed
        )
        guard response.succeeded else {
            throw ToolFailure(.failed, detail: "The search endpoint replied HTTP \(response.status).")
        }
        let rendered = WebSearchResult.render(
            provider.results(from: response, limit: context.searchResultLimit)
        )
        guard !rendered.isEmpty else {
            throw ToolFailure(
                .searchUnavailable,
                detail: "That search returned no results to read. Try different words."
            )
        }
        return .success(
            callID: call.id, toolName: call.name,
            output: "\(Self.header(for: current.route))\n\n\(rendered)"
        )
    }

    /// The chain, in one pure function over the state, so which route a turn takes is a value a test
    /// can assert rather than behaviour it has to infer. `WebSearchRouting.route` holds the order;
    /// this only turns it into the endpoint that answers to it.
    static func provider(for state: WebSearchState) -> any WebSearchProvider {
        switch state.route {
        case .ollamaCloud: return OllamaCloudSearch(token: state.cloudToken ?? "")
        case .searxng: return SearxngSearch(endpoint: state.routing.searxngURL ?? "")
        case .keyless: return KeylessSearch()
        }
    }

    /// What the model reads about where the query went — plain, and true for the route that ran.
    static func header(for route: WebSearchRoute) -> String {
        switch route {
        case .searxng:
            return "Searched your own SearXNG instance."
        case .ollamaCloud:
            return "Searched Ollama Cloud search, the search endpoint of the server this chat already uses."
        case .keyless:
            return "Searched Cairn's built-in keyless endpoint; the query went to a public search service."
        }
    }
}
