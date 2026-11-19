import Foundation
import CairnChatDomain

/// `web_fetch`: read one https page and hand back its text.
///
/// The address is a model's, so it is treated as untrusted input at every step: refused before the
/// request if it is not https or resolves to a private target, re-tested against the address the body
/// actually arrived from after any hop, capped while it downloads rather than after, and reduced to
/// readable text by `HTMLTextExtractor` so navigation and script do not arrive as though they were the
/// article. No cookie is sent and none is kept, because a fetch tool that holds cookies turns a page
/// read into a reader identified.
///
/// It shares the search tool's consent gate, and that is the point: one decision, asked once, covers both
/// ways a web tool can leave the device. A sheet for each tool would be two interruptions for one answer.
public struct WebFetchTool: ToolExecuting {
    private let transport: any WebRequesting
    private let byteLimit: Int
    /// The one question this tool may not answer for the user: may a page be read off this device.
    private let consent: WebFetchConsentRequester?

    public init(
        transport: any WebRequesting = WebHTTPTransport(),
        byteLimit: Int = 400_000,
        consent: WebFetchConsentRequester? = nil
    ) {
        self.transport = transport
        self.byteLimit = byteLimit
        self.consent = consent
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: BuiltInTool.webFetch,
            blurb: """
                Read one web page over https and return its text with the page furniture removed. \
                Only a public https address is fetched; an address on a private network is refused. \
                The page is not summarised here — you are reading what the page itself says, possibly \
                shortened, and the result says whether it was.
                """,
            parameters: ToolParameterSchema(
                properties: [
                    "url": ToolParameter(
                        kind: .string,
                        description: "The https address to read."
                    ),
                ],
                required: ["url"]
            ),
            networkClass: .publicInternet
        )
    }

    public func execute(
        _ call: ToolCall, context: ToolExecutionContext
    ) async throws -> ToolOutcome {
        let url = try WebFetchGuard.check(call.arguments["url"]?.coercedText ?? "")
        // Consent before the socket, exactly as `web_search` does it. The address is checked first because
        // a private or non-https target is refused on its own merits and must not spend a prompt; but no
        // request is built until a person has answered, so a refusal costs no DNS lookup, no bytes, no
        // latency. A build with nobody to ask gets the typed "Cairn has to ask first" refusal rather than a
        // silent yes — the default is denial, because the alternative is consent the user never gave.
        guard let consent else {
            throw ToolFailure(.internetNotAllowed, detail: Self.refusalDetail(asked: false))
        }
        guard await consent(url) else {
            throw ToolFailure(.internetNotAllowed, detail: Self.refusalDetail(asked: true))
        }
        let response = try await transport.send(
            WebFetchGuard.request(for: url, accept: "text/html"),
            byteLimit: byteLimit,
            redirectAllowed: WebFetchGuard.allowsPublicHTTPS
        )
        // Tested again on the far side of any redirect: the policy let the hop through, and this is the
        // place that knows what was actually read.
        guard WebFetchGuard.allowsPublicHTTPS(response.finalURL ?? url) else {
            throw ToolFailure(.blockedTarget)
        }
        guard response.succeeded else {
            throw ToolFailure(.failed, detail: "That address replied HTTP \(response.status).")
        }
        let text = Self.readableText(in: response)
        guard !text.isEmpty else {
            throw ToolFailure(.failed, detail: "That page returned no readable text.")
        }
        return .success(
            callID: call.id, toolName: call.name,
            output: "Read \(response.finalURL?.host ?? url.host ?? "")\n\n\(text)"
        )
    }

    /// The refusal a fetch returns when the page may not be read. Two sentences for two different facts,
    /// as in `WebSearchTool`: a person who said no has closed this, and a build with nobody to ask has not
    /// asked yet. The first tells the model to stop; the second says the question is still open, which is
    /// the only case where allowing web search in Settings changes anything.
    static func refusalDetail(asked: Bool) -> String {
        guard asked else {
            return "Cairn has to ask before a page is read off this device. Allow web search in Settings, "
                + "then read the page again."
        }
        return "The user chose not to let pages be read off this device. Do not try another address."
    }

    /// HTML through the extractor, anything else as text if it decodes as text at all. A binary body
    /// yields nothing rather than a wall of replacement characters, which a model would read as
    /// content and summarise into something the file never said.
    static func readableText(in response: WebHTTPResponse) -> String {
        if response.looksLikeHTML { return HTMLTextExtractor.extract(from: response.data) }
        guard let text = String(data: response.data, encoding: .utf8) else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: \.isLetter) else { return "" }
        return HTMLTextExtractor.cap(HTMLTextExtractor.collapse(trimmed))
    }
}
