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
}
