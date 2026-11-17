import Foundation

/// A capability a model is **stated** to have.
///
/// Badges are copied from a model's published metadata — the catalog entry, or the model's own
/// config on disk. Nothing here is inferred from a model's name or size: a guess shown as a badge
/// is a lie the user acts on. An absent field means no badge, not a defaulted one.
public enum ModelCapability: String, Sendable, Equatable, CaseIterable, Identifiable {
    case vision
    case tools
    case thinking

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .vision: return "Vision"
        case .tools: return "Tools"
        case .thinking: return "Thinking"
        }
    }

    public var symbolName: String {
        switch self {
        case .vision: return "eye"
        case .tools: return "wrench.and.screwdriver"
        case .thinking: return "brain"
        }
    }
}

/// The capability set derived from a metadata blob, with no defaults: a key that is absent yields
/// no badge.
///
/// The accepted keys are the ones MLX config files actually publish
/// (`supports_vision`, `supports_tools`, `supports_thinking`). Any other shape returns an empty set
/// rather than a guess.
public enum CapabilityReader {
    public static func read(from metadata: [String: Any]) -> [ModelCapability] {
        var found: [ModelCapability] = []
        for capability in ModelCapability.allCases {
            let key = "supports_\(capability.rawValue)"
            guard let value = metadata[key] else { continue }
            if let flag = value as? Bool, flag { found.append(capability) }
            else if let text = value as? String, text.lowercased() == "true" { found.append(capability) }
        }
        return found
    }
}
