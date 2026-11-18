import Foundation

/// The timestamp shape Cairn writes into files a user keeps.
///
/// A formatter is built per call rather than shared: `ISO8601DateFormatter` is a mutable object, so a
/// `static let` of it would be state two threads could touch at once. Exporting a chat is not a hot
/// path, so nothing is gained by sharing one and everything is gained by not having to reason about it.
public extension Date {
    /// Seconds precision in UTC, e.g. `2026-11-18T09:04:12Z` — the same shape `.cairn` files store.
    var iso8601: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: self)
    }
    /// Milliseconds precision in UTC, e.g. `2026-11-18T09:04:12.517Z` — the shape a `.cairn` file stores.
    ///
    /// Seconds are coarser than a turn. A question and its fast answer can land inside one second, and a
    /// file that wrote both as `...:12Z` would put two messages at the same instant: the export the user
    /// keeps would no longer say which came first. Fractional seconds keep the order the user experienced,
    /// and the shape stays ISO-8601, so a text editor and a `diff` still read it.
    var fileStamp: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: self)
    }

    /// The exact reverse of `fileStamp`. nil for anything that is not that shape, so a reader can refuse
    /// rather than guess at a timestamp.
    static func fileStampValue(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: text)
    }

}
