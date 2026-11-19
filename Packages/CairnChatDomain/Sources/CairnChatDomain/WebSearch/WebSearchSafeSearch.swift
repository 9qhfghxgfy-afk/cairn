import Foundation

/// How strict a search's results should be about explicit material.
///
/// Both transports Cairn speaks to number this the same way — `safesearch=0|1|2` on DuckDuckGo's HTML
/// endpoint and on SearXNG's JSON endpoint — so one enum carries one wire value and the UI text, and
/// there is no place for the two to disagree about what "moderate" means.
public enum WebSearchSafeSearch: Int, Sendable, Equatable, Codable, CaseIterable {
    case off = 0
    case moderate = 1
    case strict = 2

    /// The number both endpoints expect.
    public var wireValue: Int { rawValue }

    public var label: String {
        switch self {
        case .off: return "Off"
        case .moderate: return "Moderate"
        case .strict: return "Strict"
        }
    }

    /// What the filter does, said plainly enough that turning it off is an informed choice.
    public var explanation: String {
        switch self {
        case .off: return "No filtering. Results may include explicit material."
        case .moderate: return "Filters explicit results and thumbnails."
        case .strict: return "Strongest filtering the provider offers."
        }
    }

    /// Moderate is the shipped answer: a search tool in a chat app should not surface explicit material
    /// to someone who never chose to see it, and a user who wants none of it moves one control.
    public static let `default`: WebSearchSafeSearch = .moderate
}
