import Foundation

/// Which published response shape a turn is answered in.
///
/// Four of them, because two dialects each have a chat-shaped and a completion-shaped endpoint, and
/// the shapes are **not interchangeable**: an Ollama client on `/api/generate` reads `response`, and
/// one on `/api/chat` reads `message.content`. Answering either with the other's field is a server
/// that appears to produce an empty answer.
public enum ShareStreamShape: String, Sendable, Equatable, CaseIterable {
    case ollamaChat
    case ollamaGenerate
    case openAIChat
    case openAICompletion

    public var dialect: ShareDialect {
        switch self {
        case .ollamaChat, .ollamaGenerate: return .ollama
        case .openAIChat, .openAICompletion: return .openAI
        }
    }

    /// The shape a route is answered in, or nil for a route that runs no turn.
    public static func forEndpoint(_ endpoint: ShareEndpoint) -> ShareStreamShape? {
        switch endpoint {
        case .chat(let dialect): return dialect == .ollama ? .ollamaChat : .openAIChat
        case .generate: return .ollamaGenerate
        case .completion: return .openAICompletion
        case .version, .modelList, .preflight, .unknown: return nil
        }
    }
}
