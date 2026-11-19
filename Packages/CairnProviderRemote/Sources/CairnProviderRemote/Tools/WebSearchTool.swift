import Foundation
import CairnChatDomain

/// `web_search`: one query to the provider the user selected, and a numbered result list back.
///
/// Four rules hold this tool honest, and they are why it is written the way it is.
///
/// - **Only the query leaves.** Every provider builds its request from the `query` argument alone — no
///   transcript, no attachment, no persona, and no credential except the one the selected endpoint needs.
///   `WebSearchToolTests` asserts that on the built request rather than trusting this sentence.
/// - **One provider, chosen by the user.** There is no precedence and no fallback. If the active provider
///   fails, this returns a typed failure naming that provider and the reason; it never quietly searches
///   somewhere else, because a result from a provider the user did not pick is a disclosure they cannot see.
/// - **Consent before the socket.** A public-internet provider that has not been agreed to gets no request
///   at all — not a request that is cancelled, and not a request whose result is withheld.
/// - **A changed provider is a break, not an empty answer.** A reply that cannot be read is
///   `unrecognizedResponse`. "No results" is reserved for a provider that genuinely found nothing, because a
///   model told the second will report to the user that nothing exists.
public struct WebSearchTool: ToolExecuting {
    private let state: WebSearchStateReader
    private let transport: any WebRequesting
    private let throttle: WebSearchThrottle
    /// The one question the tool may not answer for the user: may this provider have my query.
    private let consent: WebSearchConsentRequester?

    public init(
        state: @escaping WebSearchStateReader,
        transport: any WebRequesting = WebHTTPTransport(),
        throttle: WebSearchThrottle = WebSearchThrottle(),
        consent: WebSearchConsentRequester? = nil
    ) {
        self.state = state
        self.transport = transport
        self.throttle = throttle
        self.consent = consent
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.webSearch,
            blurb: """
                Search the web with one short query and get numbered results back, each with its URL \
                and a snippet the provider itself wrote. Only the query is sent; nothing from this \
                conversation goes with it, and the answer says which provider it came from. Use it when \
                the answer is not already here, and name which result you used. A result you did not read \
                tells you nothing — pass its URL to web_fetch if you need its contents.
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
            // The widest class this tool can reach. The badge the user sees is driven by the active
            // provider's own class, not by this value; declaring the maximum is what keeps the outbound
            // acknowledgement in front of a provider switch.
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
        let profile = current.provider
        let providerName = profile.displayName

        // Consent is checked before a request is even built, so a refusal costs nothing and sends nothing.
        switch current.consent {
        case .denied:
            let failure = WebSearchFailure.permissionDenied
            throw ToolFailure(failure.toolError, detail: failure.modelText(providerName: providerName))
        case .undecided:
            // Not a refusal yet — a question. The app asks a person; a build with nobody to ask gets the
            // typed refusal instead of a silent yes. Either way the request has not been built, and a
            // refusal costs no socket, no bytes and no latency.
            let allowed: Bool
            if let consent { allowed = await consent(profile) } else { allowed = false }
            guard allowed else {
                throw ToolFailure(
                    .internetNotAllowed,
                    detail: Self.refusalDetail(providerName: providerName, asked: consent != nil)
                )
            }
        case .granted:
            break
        }

        guard let provider = WebSearchProviderFactory.make(profile: profile) else {
            let failure = WebSearchFailure.providerUnavailable
            throw ToolFailure(failure.toolError, detail: failure.modelText(providerName: providerName))
        }

        // The app-wide count, not a per-turn guess: it is one number the user set on the Web Search screen,
        // and it is the same whatever provider happens to be active.
        let limit = current.resultCount
        let cacheKey = WebSearchCourtesy.key(
            providerID: profile.id, query: query, safeSearch: profile.safeSearch,
            timeRange: profile.timeRange, categories: profile.categories,
            language: profile.language, resultCount: limit
        )
        if let cached = await throttle.cachedResults(for: cacheKey), !cached.isEmpty {
            return .success(
                callID: call.id, toolName: call.name,
                output: "\(Self.header(for: profile))\n\n\(Self.cachedNote)\n\n"
                    + WebSearchResult.render(cached)
            )
        }

        let dispatch = provider.dispatch(for: query, limit: limit, credential: current.credential)
        let request: URLRequest
        let byteLimit: Int
        switch dispatch {
        case .failure(let failure):
            throw ToolFailure(failure.toolError, detail: failure.modelText(providerName: providerName))
        case .request(let built, let cap):
            request = built
            byteLimit = cap
        }

        // The courtesy gap is waited out before the socket opens, and a cancellation during that wait stops
        // the request rather than releasing it late.
        guard await throttle.beginRequest() else { throw ToolFailure(.cancelled) }

        let response: WebHTTPResponse
        do {
            response = try await transport.send(
                request, byteLimit: byteLimit, redirectAllowed: provider.redirectAllowed
            )
        } catch {
            if Self.isCancellation(error) { throw ToolFailure(.cancelled) }
            let failure = WebSearchFailure.transport(error)
            throw ToolFailure(failure.toolError, detail: failure.modelText(providerName: providerName))
        }
        guard response.succeeded else {
            let failure = WebSearchFailure.response(status: response.status)
            throw ToolFailure(failure.toolError, detail: failure.modelText(providerName: providerName))
        }

        switch provider.read(response, limit: limit) {
        case .results(let found):
            await throttle.remember(found, for: cacheKey)
            return .success(
                callID: call.id, toolName: call.name,
                output: "\(Self.header(for: profile))\n\n\(WebSearchResult.render(found))"
            )
        case .empty:
            // A success, deliberately. An honest empty is information; a typed failure here would read to
            // the model as "searching broke" and stop it rephrasing.
            return .success(
                callID: call.id, toolName: call.name,
                output: "\(Self.header(for: profile))\n\n\(providerName) returned nothing for those "
                    + "words. That is a real answer, not an error — try different words, or answer "
                    + "without searching."
            )
        case .failure(let failure):
            throw ToolFailure(failure.toolError, detail: failure.modelText(providerName: providerName))
        }
    }

    /// The chain, in one pure function over the row, so which provider a turn uses is a value a test can
    /// assert rather than behaviour it has to infer. There is no ordering to test: the active row is the
    /// provider, and nothing else is consulted.
    static func provider(for profile: WebSearchProviderProfile) -> (any WebSearchProvider)? {
        WebSearchProviderFactory.make(profile: profile)
    }

    /// What the model reads about where the query went, plus the provider's own attribution. Cairn states
    /// the third-party relationship in the same words to the model and to the user, so a model naming the
    /// source is not repeating something Cairn left out.
    static func header(for profile: WebSearchProviderProfile) -> String {
        let named: String
        switch profile.kind {
        case .duckDuckGo:
            named = "Searched DuckDuckGo through Cairn's built-in provider."
        case .searxng:
            named = "Searched \(profile.displayName), your own SearXNG instance."
        case .ollamaCloud:
            named = "Searched \(profile.displayName), billed by Ollama under your profile."
        }
        guard let note = WebSearchAttribution.note(for: profile.kind) else { return named }
        return "\(named) \(note)"
    }

    /// The refusal a search returns when the query may not go out. Two different sentences, because the
    /// two conditions are different facts: a person who said no has closed this provider, and a build with
    /// nobody to ask has simply not asked yet. The first tells the model to stop; the second says the
    /// question is still open, which is the only case where allowing it in Settings changes anything.
    static func refusalDetail(providerName: String, asked: Bool) -> String {
        guard asked else {
            return "Cairn has to ask before \(providerName) receives a query. Allow it in Settings, "
                + "then search again."
        }
        return WebSearchFailure.permissionDenied.modelText(providerName: providerName)
    }

    /// Cached answers are labelled as cached. A list a minute old may still be true, but a model should not
    /// present it as though it had just been asked.
    static var cachedNote: String {
        "These results came from Cairn's memory of an identical search moments ago, not a new request."
    }

    /// Cancellation is the turn stopping, not a provider failing, and it has to stay that way in the record.
    static func isCancellation(_ error: any Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let bridged = error as NSError
        return bridged.domain == NSURLErrorDomain && bridged.code == NSURLErrorCancelled
    }
}

