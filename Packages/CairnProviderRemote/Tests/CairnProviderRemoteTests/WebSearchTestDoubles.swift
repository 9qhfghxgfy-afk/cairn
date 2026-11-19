import Foundation
import XCTest
import CairnChatDomain
@testable import CairnProviderRemote

/// The search-tool builders that need a consent answer, which `searchState` alone cannot express: a row
/// nobody has been asked about, a row that was asked and refused, and a build with nobody to ask.
///
/// A requester is a `@MainActor` closure because asking is a UI act. The recorder is the test's side of
/// that: it answers, and it keeps the order. "Asked and refused" and "never asked" are different facts, and
/// only the recorder can tell them apart afterwards.
///
/// A test that counts requests across two tools hands the recorder in. Each tool would otherwise build its
/// own, and the second tool's requests would be counted by a recorder the test never looks at — which reads
/// as "one request" no matter what the tool did.
func searchTool(
    _ state: WebSearchState,
    reply: WebHTTPResponse = .json(
        #"{"results":[{"title":"Rain","url":"https://example.com/one","snippet":"Wet."}]}"#
    ),
    throws error: (any Error)? = nil,
    throttle: WebSearchThrottle? = nil,
    consent: WebSearchConsentRequester? = nil,
    transport sharedTransport: RecordingWebTransport? = nil
) -> (WebSearchTool, RecordingWebTransport) {
    let transport = sharedTransport ?? RecordingWebTransport(reply: reply, throws: error)
    let tool = WebSearchTool(
        state: { state }, transport: transport, throttle: throttle ?? WebSearchThrottle(),
        consent: consent
    )
    return (tool, transport)
}

func searchCall(_ query: String) -> ToolCall {
    ToolCall(id: "c1", name: BuiltInTool.webSearch, arguments: ["query": .text(query)])
}

/// The chat-level acknowledgement is on, so a refusal in these tests can only ever be about the provider.
var armedContext: ToolExecutionContext {
    ToolExecutionContext(toolsEnabled: true, outboundWebAllowed: true)
}

/// A public-internet row over plaintext, which the settings screen refuses to save. The tool still has to
/// refuse it rather than badge it, in case a stored row outlives the rule that wrote it.
func plaintextPublicRow(name: String = "Public") -> WebSearchProviderProfile {
    WebSearchProviderProfile(
        kind: .searxng, displayName: name, baseURLString: "http://search.example.com"
    )
}

/// Records that the user was asked, and answers. Sendable by hand: one counter, written from the main
/// actor, read by the test only after the tool call has returned.
final class ConsentRecorder: @unchecked Sendable {
    private var names: [String] = []
    private let answer: Bool

    init(answer: Bool) { self.answer = answer }

    @MainActor
    func request(_ profile: WebSearchProviderProfile) async -> Bool {
        names.append(profile.displayName)
        return answer
    }

    var askedProviderNames: [String] { names }
    var askedCount: Int { names.count }
}

/// Asserts the typed failure a search throws, so a change of case cannot slip through as "still fails".
/// The expected value is named apart from `error`: inside the trailing `catch`, `error` is whatever the
/// tool actually threw, and that has no `rawValue` to compare against.
///
/// `@MainActor` because the body is a plain closure, not a `@Sendable` one, and a test hands it in while it
/// is on the main actor. A nonisolated `async` helper would have to receive it across isolation, which a
/// non-Sendable closure cannot do — the checker calls that a data race rather than letting it pass. Staying
/// on the main actor keeps the hand-off local, which is also where asking for consent lives.
@MainActor
func expectSearchFailure(_ expected: ToolError, _ body: () async throws -> ToolOutcome) async {
    do {
        _ = try await body()
        XCTFail("expected \(expected.rawValue)")
    } catch let thrown as ToolFailure {
        XCTAssertEqual(thrown.error, expected)
    } catch {
        XCTFail("expected \(expected.rawValue), threw a different kind of error")
    }
}
