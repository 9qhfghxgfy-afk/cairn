import Foundation

/// What a request path means to the share surface.
///
/// One table, so the answer an unknown path gets is decided in the same place the known ones are.
public enum ShareEndpoint: Sendable, Equatable {
    /// `GET /api/version` — Ollama only.
    case version
    /// `GET /api/tags` or `GET /v1/models`.
    case modelList(dialect: ShareDialect)
    /// `POST /api/chat` or `POST /v1/chat/completions`.
    case chat(dialect: ShareDialect)
    /// `POST /api/generate` — Ollama's completion-shaped turn.
    case generate
    /// `POST /v1/completions` — the legacy OpenAI completion turn.
    case completion
    /// A preflight from a browser, which carries no turn and gets no turn.
    case preflight
    /// Anything else. Answered 404 in the dialect of the path, so a client looking at `/api/x`
    /// gets an Ollama-shaped error and one looking at `/v1/x` gets an OpenAI-shaped one.
    case unknown(path: String)

    public var dialect: ShareDialect? {
        switch self {
        case .version, .generate: return .ollama
        case .completion: return .openAI
        case .modelList(let dialect), .chat(let dialect): return dialect
        case .preflight, .unknown: return nil
        }
    }

    /// The dialect an error answer should be written in, defaulting to Ollama because the paths
    /// this surface owns are Ollama's first (`/api/…`) and an unqualified client is an Ollama one.
    public var errorDialect: ShareDialect { dialect ?? .ollama }
}

public enum ShareRouting {
    /// Method + path → endpoint. Paths are compared exactly; a query string is not part of a route.
    public static func endpoint(method: String, path: String) -> ShareEndpoint {
        let verb = method.uppercased()
        if verb == "OPTIONS" { return .preflight }
        switch (verb, path) {
        case ("GET", "/api/version"): return .version
        case ("GET", "/api/tags"): return .modelList(dialect: .ollama)
        case ("GET", "/v1/models"): return .modelList(dialect: .openAI)
        case ("POST", "/api/chat"): return .chat(dialect: .ollama)
        case ("POST", "/api/generate"): return .generate
        case ("POST", "/v1/chat/completions"): return .chat(dialect: .openAI)
        case ("POST", "/v1/completions"): return .completion
        default: return .unknown(path: path)
        }
    }

    /// A path this surface answers, in either dialect — used by the status line and the guide text.
    public static var answeredPaths: [String] {
        ["/api/version", "/api/tags", "/api/chat", "/api/generate", "/v1/models", "/v1/chat/completions", "/v1/completions"]
    }
}
