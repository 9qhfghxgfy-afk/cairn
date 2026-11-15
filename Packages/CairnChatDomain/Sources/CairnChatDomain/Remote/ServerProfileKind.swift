import Foundation

/// What kind of server a profile points at. Only public, documented wire formats
/// are spoken (Ollama HTTP API, OpenAI-compatible /v1/chat/completions) —
/// interface compatibility, not copied expression.
public enum ServerProfileKind: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case ollama
    case openAICompatible

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .openAICompatible: return "OpenAI-compatible"
        }
    }
}
