import Foundation

/// A seed the user owns. Recorded here (2026-11-16) because the two modes are easy to conflate:
///
/// - `random` — **Cairn chose the number.** It is shown in the field and sent on every request,
///   and the Randomize button replaces it. Replaying the same chat replays the same seed.
/// - `fixed` — **the user typed the number.** Cairn never changes it.
///
/// What `random` deliberately does *not* mean is "a different seed every turn". A server-side
/// re-roll (Ollama's `-1` sentinel) makes a turn unreplayable, and a Cairn node has to replay and
/// export as it was. The value that produced the answer is the value that is stored.
///
/// Absent (no `SeedSetting` in `SamplingConfig`) is the third state: no seed key is sent at all,
/// and the server applies its own rule.
public struct SeedSetting: Sendable, Equatable, Codable {
    public enum Mode: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
        case random
        case fixed

        public var id: String { rawValue }
        public var displayName: String { self == .random ? "Random" : "Fixed" }

        /// Who owns the number, in the words the sheet shows beside the field. The distinction is the
        /// whole point of the type, so it is stated in the domain rather than improvised per screen.
        public var note: String {
            switch self {
            case .random: return "Cairn chose this number; it is still sent on every request."
            case .fixed: return "You typed this number; Cairn will not change it."
            }
        }
    }

    public var mode: Mode
    public var value: Int

    public init(mode: Mode, value: Int) {
        self.mode = mode
        self.value = value
    }

    /// The Randomize button: keeps the mode, replaces the number. A candidate is passed in rather
    /// than read from a global RNG so the call site — and the test — owns the randomness.
    public func replacingSeed(with candidate: Int) -> SeedSetting {
        SeedSetting(mode: mode, value: candidate)
    }

    /// A fresh "Cairn chose it" seed. `candidate` comes from the caller for the same reason.
    public static func random(from candidate: Int) -> SeedSetting {
        SeedSetting(mode: .random, value: candidate)
    }

    public static func fixed(_ value: Int) -> SeedSetting {
        SeedSetting(mode: .fixed, value: value)
    }
}
