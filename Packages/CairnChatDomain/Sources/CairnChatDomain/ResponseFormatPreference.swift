import Foundation

/// The answer shape the response-format block states. A preference, never content: nothing the
/// user wrote or received is included in what gets injected.
public enum ResponseFormatPreference: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case plain
    case markdown
    case terse

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plain: return "Plain prose"
        case .markdown: return "Markdown"
        case .terse: return "As short as possible"
        }
    }
}
