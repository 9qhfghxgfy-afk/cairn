import Foundation

/// What kind of server a profile points at. Only public, documented wire formats are spoken
/// (Ollama's HTTP API, LM Studio's REST API, OpenAI-compatible `/v1/chat/completions`) —
/// interface compatibility, not copied expression.
///
/// Every kind's endpoints and capability flags are declared once in `ServerBackend`, so the UI
/// derives each button from one map instead of from scattered switches. Adding a kind means
/// adding a case, its backend entry, and a wire in `CairnProviderRemote` — nothing else.
public enum ServerProfileKind: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case ollama
    /// LM Studio's own server: its native REST surface for the model list and lifecycle, plus
    /// the OpenAI-compatible chat endpoint it serves on the same port.
    case lmStudio
    case openAICompatible
    /// Ollama's hosted API. Off by default and `.publicInternet`: it is inert until the user
    /// opts in to outbound requests **and** supplies a Keychain-backed key.
    case ollamaCloud

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .openAICompatible: return "OpenAI-compatible"
        case .ollamaCloud: return "Ollama Cloud"
        }
    }

    /// The declared surface for this kind: endpoints, capabilities, and how the Add-server form
    /// should prefill.
    public var backend: ServerBackend { ServerBackend.backend(for: self) }

    /// A saved record whose kind this build does not know (a record written by a newer build).
    /// OpenAI-compatible is the honest fallback: it is the narrowest dialect — it only lists and
    /// chats — so an unknown kind cannot be offered an endpoint it does not have.
    public static let unknownFallback: ServerProfileKind = .openAICompatible
}
