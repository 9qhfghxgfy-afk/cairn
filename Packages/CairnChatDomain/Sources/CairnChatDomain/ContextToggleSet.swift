import Foundation

/// Which facts Cairn adds to the system prompt, and which it withholds. Every entry is a user
/// choice — nothing here is injected behind the user's back.
///
/// Two groups, and the difference matters:
/// - **Always-injected** entries appear on every turn while switched on.
/// - **Conditionally-injected** entries appear only when the feature they describe is actually
///   active for the turn. A "use your tools" reminder on a turn with no tools would teach the model
///   to pretend it has one, so the toggle being on is not enough.
///
/// The defaults are the ones recorded in `docs/PARITY.md` §3.3: Date on, Time and timezone off,
/// Platform on, Language on, Tool Guidance on, Force Web Fetch off, File Context on, Image Context
/// on. The three additions are the non-identifying items proposed in `docs/PARITY.md` §2.
public struct ContextToggleSet: Sendable, Equatable, Codable {
    public var date: Bool
    public var timeAndTimezone: Bool
    public var platform: Bool
    public var language: Bool
    public var localeRegion: Bool
    public var capabilitySummary: Bool
    public var responseFormat: Bool

    public var toolGuidance: Bool
    public var forceWebFetch: Bool
    public var fileContext: Bool
    public var imageContext: Bool

    public init(
        date: Bool = true,
        timeAndTimezone: Bool = false,
        platform: Bool = true,
        language: Bool = true,
        localeRegion: Bool = true,
        capabilitySummary: Bool = true,
        responseFormat: Bool = true,
        toolGuidance: Bool = true,
        forceWebFetch: Bool = false,
        fileContext: Bool = true,
        imageContext: Bool = true
    ) {
        self.date = date
        self.timeAndTimezone = timeAndTimezone
        self.platform = platform
        self.language = language
        self.localeRegion = localeRegion
        self.capabilitySummary = capabilitySummary
        self.responseFormat = responseFormat
        self.toolGuidance = toolGuidance
        self.forceWebFetch = forceWebFetch
        self.fileContext = fileContext
        self.imageContext = imageContext
    }

    public static let `default` = ContextToggleSet()

    /// Nothing injected at all — a chat that sends the persona and nothing else.
    public static let off = ContextToggleSet(
        date: false, timeAndTimezone: false, platform: false, language: false,
        localeRegion: false, capabilitySummary: false, responseFormat: false,
        toolGuidance: false, forceWebFetch: false, fileContext: false, imageContext: false
    )

    /// The always-injected group, in the order the sheet lists it.
    public static let alwaysOnKeys: [ContextKey] =
        [.date, .timeAndTimezone, .platform, .language, .localeRegion,
         .capabilitySummary, .responseFormat]
    public static let conditionalKeys: [ContextKey] =
        [.toolGuidance, .forceWebFetch, .fileContext, .imageContext]

    public func value(_ key: ContextKey) -> Bool {
        switch key {
        case .date: return date
        case .timeAndTimezone: return timeAndTimezone
        case .platform: return platform
        case .language: return language
        case .localeRegion: return localeRegion
        case .capabilitySummary: return capabilitySummary
        case .responseFormat: return responseFormat
        case .toolGuidance: return toolGuidance
        case .forceWebFetch: return forceWebFetch
        case .fileContext: return fileContext
        case .imageContext: return imageContext
        }
    }

    public mutating func setValue(_ key: ContextKey, _ on: Bool) {
        switch key {
        case .date: date = on
        case .timeAndTimezone: timeAndTimezone = on
        case .platform: platform = on
        case .language: language = on
        case .localeRegion: localeRegion = on
        case .capabilitySummary: capabilitySummary = on
        case .responseFormat: responseFormat = on
        case .toolGuidance: toolGuidance = on
        case .forceWebFetch: forceWebFetch = on
        case .fileContext: fileContext = on
        case .imageContext: imageContext = on
        }
    }

    public var enabledCount: Int {
        ContextKey.allCases.filter { value($0) }.count
    }
}
