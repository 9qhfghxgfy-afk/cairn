import Foundation

/// The reference value each control shows when it is **unset**.
///
/// These are Cairn's own published reference points, not values Cairn sends. An unset control
/// renders at its reference value in a muted style and is omitted from the outbound request, so
/// the server's own default applies — which is the only way "the server decides" can mean
/// anything. Keeping them in one place is what lets the sheet, the badge count, and the tests
/// agree on what "default" means.
public enum SamplingReference {
    public static let temperature = 0.80
    public static let topP = 0.90
    public static let minP = 0.00
    public static let topK = 40
    public static let repeatPenalty = 1.10
    public static let repeatLastN = 64
    public static let contextWindow = 8192

    /// The Context Size control snaps to this ladder — 2K through 256K, doubling. A free-form
    /// number invites a value the server cannot honour and the memory budget cannot fit.
    public static let contextWindowLadder: [Int] =
        [2048, 4096, 8192, 16_384, 32_768, 65_536, 131_072, 262_144]

    public static let temperatureRange = 0.0...2.0
    public static let topPRange = 0.0...1.0
    public static let minPRange = 0.0...1.0
    public static let repeatPenaltyRange = 0.0...3.0

    /// Nearest rung of the ladder. Anything off-ladder snaps rather than being rejected, because
    /// a stored value from another build is not the user's mistake.
    public static func snapContextWindow(_ tokens: Int) -> Int {
        contextWindowLadder.min(by: { abs($0 - tokens) < abs($1 - tokens) }) ?? contextWindow
    }

    /// `2048 -> "2K"`, `262_144 -> "256K"` — the label the slider rungs are drawn with.
    public static func contextLabel(_ tokens: Int) -> String {
        guard tokens >= 1024 else { return "\(tokens)" }
        let thousands = tokens / 1024
        return tokens % 1024 == 0 ? "\(thousands)K" : String(format: "%.1fK", Double(tokens) / 1024)
    }
}
