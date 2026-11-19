import Foundation

/// The two wire dialects this phone speaks when it is the server.
///
/// Cairn serves **published** HTTP shapes — Ollama's `/api/*` and the OpenAI-compatible
/// `/v1/*` surface — so an ordinary client written for either works unchanged. Nothing here is
/// a private format: that is the whole reason a shared model is useful to another machine.
public enum ShareDialect: String, Sendable, Equatable, CaseIterable, Codable {
    case ollama
    case openAI

    /// Content type of a **complete** body.
    public var contentType: String {
        switch self {
        case .ollama: return "application/x-ndjson"
        case .openAI: return "application/json"
        }
    }

    /// Content type of a **streamed** answer. Ollama answers a streaming request with NDJSON and
    /// a non-streaming one with JSON; an OpenAI-compatible client is answered with SSE either way
    /// only when it asked for a stream, and with plain JSON when it did not.
    public var streamContentType: String {
        switch self {
        case .ollama: return "application/x-ndjson"
        case .openAI: return "text/event-stream"
        }
    }

    /// The path that lists what is on offer.
    public var listPath: String {
        switch self {
        case .ollama: return "/api/tags"
        case .openAI: return "/v1/models"
        }
    }

    /// The path a chat turn arrives on.
    public var chatPath: String {
        switch self {
        case .ollama: return "/api/chat"
        case .openAI: return "/v1/chat/completions"
        }
    }

    /// The name this surface puts in a `Server:` response head. Deliberately the app's own name:
    /// a client must be able to tell that it is talking to a phone running Cairn and not to a
    /// desktop Ollama install.
    public static let serverToken = "Cairn"
}
