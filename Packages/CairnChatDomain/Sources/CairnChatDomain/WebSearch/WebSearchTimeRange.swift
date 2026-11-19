import Foundation

/// How far back a search may reach, when the user wants recency rather than relevance.
///
/// SearXNG takes this as `time_range=day|month|year`. DuckDuckGo's HTML endpoint has no equivalent
/// parameter, so the DuckDuckGo route **drops it rather than inventing a substitute** — a control that
/// silently does nothing on one provider is worse than a control that is only offered where it works.
public enum WebSearchTimeRange: String, Sendable, Equatable, Codable, CaseIterable {
    case day
    case week
    case month
    case year

    /// The value SearXNG expects. `week` is sent as its closest supported rung rather than being
    /// dropped, because a user who asked for a week does not want a year.
    public var searxngValue: String {
        self == .week ? "month" : rawValue
    }

    /// DuckDuckGo's own letter codes for the same idea (`df=d|w|m|y`).
    ///
    /// The two spellings live here rather than in the transports so one enum remains the single statement
    /// of what "past month" means, whatever the provider calls it.
    public var duckDuckGoValue: String {
        switch self {
        case .day: return "d"
        case .week: return "w"
        case .month: return "m"
        case .year: return "y"
        }
    }

    public var label: String {
        switch self {
        case .day: return "Past day"
        case .week: return "Past week"
        case .month: return "Past month"
        case .year: return "Past year"
        }
    }
}
