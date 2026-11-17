import Foundation

/// One injected-context control, named once, so the sheet, the assembler, and the `(i)` copy use
/// the same words for the same thing.
public enum ContextKey: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case date
    case timeAndTimezone
    case platform
    case language
    case localeRegion
    case capabilitySummary
    case responseFormat
    case toolGuidance
    case forceWebFetch
    case fileContext
    case imageContext

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .date: return "Date"
        case .timeAndTimezone: return "Time and timezone"
        case .platform: return "Platform"
        case .language: return "Language"
        case .localeRegion: return "Locale region"
        case .capabilitySummary: return "Capability summary"
        case .responseFormat: return "Response format"
        case .toolGuidance: return "Tool Guidance"
        case .forceWebFetch: return "Force Web Fetch"
        case .fileContext: return "File Context"
        case .imageContext: return "Image Context"
        }
    }

    /// True when the block needs a live feature to be worth writing at all.
    public var isConditional: Bool {
        switch self {
        case .toolGuidance, .forceWebFetch, .fileContext, .imageContext: return true
        default: return false
        }
    }

    public var explainer: String {
        switch self {
        case .date:
            return "Today's date. The model has no clock of its own, so without this it guesses, "
                + "and confidently guesses wrong."
        case .timeAndTimezone:
            return "The hour and the timezone name. Off by default: it is the most identifying item "
                + "in this list, and most questions do not need the hour."
        case .platform:
            return "Tells the model it is answering inside Cairn on iPhone or iPad, so it stops "
                + "offering desktop steps that do not exist here."
        case .language:
            return "The device language code, so the model can tell a translation request from a "
                + "question asked in that language."
        case .localeRegion:
            return "The region code only — never a name, never a location. Used for units and date "
                + "conventions."
        case .capabilitySummary:
            return "What this turn can actually do: streaming, thinking, tools, images, context "
                + "size. Without it a model will claim abilities it has not been given."
        case .responseFormat:
            return "The shape you want answers in — plain prose, Markdown, or as short as possible. "
                + "The preference only; nothing you wrote is included."
        case .toolGuidance:
            return "Added only on a turn that really has tools. It says use them rather than guess, "
                + "and never report a result a tool did not return."
        case .forceWebFetch:
            return "Added only when a web search runs. It requires the model to open at least one "
                + "result URL and answer from that page rather than from memory."
        case .fileContext:
            return "Added only when documents are attached. It requires the answer to be grounded "
                + "in them and to say so when they do not cover the question."
        case .imageContext:
            return "Added only when images are attached. It requires the model to describe what is "
                + "actually visible before concluding anything."
        }
    }
}
