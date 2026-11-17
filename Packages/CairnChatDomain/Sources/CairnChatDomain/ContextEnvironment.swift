import Foundation

/// The clock, as a value. Everything time-shaped in the prompt comes through here so a test can
/// pin it: an assembler that reads the wall clock cannot assert that "Date: off" really omits the
/// date, because the assertion would pass or fail depending on when the suite ran.
public struct ContextClock: Sendable, Equatable {
    public var date: Date
    public var timeZoneIdentifier: String

    public init(
        date: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// A pinned instant for tests and previews, written as ISO 8601 so the fixture reads as a date
    /// rather than as a number of seconds.
    public static func pinned(iso8601: String, timeZone: String = "UTC") -> ContextClock {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return ContextClock(
            date: formatter.date(from: iso8601) ?? Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: timeZone
        )
    }
}

/// The non-identifying device facts Cairn is willing to state. A model name, a device name, an
/// identifier — none of that exists in this type, which is what makes it safe to send.
public struct DeviceContext: Sendable, Equatable {
    public var platformName: String
    public var languageCode: String
    public var regionCode: String

    public init(platformName: String, languageCode: String, regionCode: String) {
        self.platformName = platformName
        self.languageCode = languageCode
        self.regionCode = regionCode
    }
}

/// Clock plus device, read once per turn. `current()` reads the live values; every caller that
/// needs determinism builds the value instead.
public struct ContextEnvironment: Sendable, Equatable {
    public var clock: ContextClock
    public var device: DeviceContext

    public init(clock: ContextClock, device: DeviceContext) {
        self.clock = clock
        self.device = device
    }

    public static func current(now: Date = Date()) -> ContextEnvironment {
        let locale = Locale.current
        // Region and language codes only — never a display name, never a location, never an
        // identifier. Both are nil on a stripped-down locale, and an empty value means the block
        // is left out rather than written as a blank.
        let region = locale.region?.identifier ?? ""
        let language = locale.language.languageCode?.identifier ?? ""
        return ContextEnvironment(
            clock: ContextClock(date: now),
            device: DeviceContext(
                platformName: Self.platformName,
                languageCode: language,
                regionCode: region
            )
        )
    }

    /// Read from the compilation target rather than from UIKit, which this module may not import.
    public static var platformName: String {
        #if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac { return "macOS" }
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "unknown platform"
        #endif
    }
}
