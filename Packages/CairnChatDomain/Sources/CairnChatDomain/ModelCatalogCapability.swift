import Foundation

/// A capability the Download tab can be filtered by.
///
/// A badge is only ever copied from something the publisher states: a repository's own
/// `config.json` block (`vision_config`, `audio_config`), or the capability filter the model
/// library itself lists for a family. Nothing here is inferred from a model's name or its size —
/// a guessed badge is a claim the user acts on, and a phone that cannot see an image will fail a
/// turn that promised it could.
///
/// The Download tab lists these as chips and a card may carry several, so the set is the unit a
/// filter works on: chips narrow the list, they never widen it.
public enum ModelCatalogCapability: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case vision
    case tools
    case thinking
    case audio

    public var id: String { rawValue }

    /// The word on the chip and on the badge. Short, because it sits inline after a model name.
    public var label: String {
        switch self {
        case .vision: return "Vision"
        case .tools: return "Tools"
        case .thinking: return "Thinking"
        case .audio: return "Audio"
        }
    }

    /// The mark drawn beside the label. A name UIKit resolves or does not; `ModelSymbolTests`
    /// asks it rather than trusting the string.
    public var symbolName: String {
        switch self {
        case .vision: return "eye"
        case .tools: return "wrench.and.screwdriver"
        case .thinking: return "brain.head.profile"
        case .audio: return "headphones"
        }
    }
}
