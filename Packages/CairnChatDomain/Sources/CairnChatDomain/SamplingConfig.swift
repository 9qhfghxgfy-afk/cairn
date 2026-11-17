import Foundation

/// The sampling knobs of one chat, where **every knob is optional**.
///
/// `nil` means "unset": the control shows its reference value muted, and the key is left out of
/// the outbound request so the server's own default applies. A non-nil value is "configured":
/// the control shows it in full colour and the key goes on the wire — provided the active server
/// kind supports it, which `SamplingSupport` decides. Those two rules (omit when unset, strip when
/// unsupported) are the whole point of this type, so they live in one place rather than in the
/// encoders.
public struct SamplingConfig: Sendable, Equatable, Codable {
    public var temperature: Double?
    public var topP: Double?
    public var minP: Double?
    public var topK: Int?
    public var maxTokens: Int?
    public var repeatPenalty: Double?
    public var repeatLastN: Int?
    public var seed: SeedSetting?
    public var contextWindow: Int?

    public init(
        temperature: Double? = nil,
        topP: Double? = nil,
        minP: Double? = nil,
        topK: Int? = nil,
        maxTokens: Int? = nil,
        repeatPenalty: Double? = nil,
        repeatLastN: Int? = nil,
        seed: SeedSetting? = nil,
        contextWindow: Int? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.minP = minP
        self.topK = topK
        self.maxTokens = maxTokens
        self.repeatPenalty = repeatPenalty
        self.repeatLastN = repeatLastN
        self.seed = seed
        self.contextWindow = contextWindow
    }

    /// Everything unset: a new chat that inherits nothing from Cairn and asks for nothing.
    public static let unset = SamplingConfig()

    /// How many knobs this chat explicitly configures — the number behind the
    /// "N options configured" badge in Settings. Persona and the injected-context toggles are
    /// counted separately; this count is only the sampling knobs, because that is the set whose
    /// absence changes what a server actually receives.
    public var configuredOptionCount: Int {
        SamplingKey.allCases.filter { $0.isSet(in: self) }.count
    }

    public var hasOverrides: Bool { configuredOptionCount > 0 }

    public func isConfigured(_ key: SamplingKey) -> Bool { key.isSet(in: self) }

    public mutating func clear(_ key: SamplingKey) { key.clear(in: &self) }

    /// Copies the knobs the given setting explicitly configures onto this one and clears the rest,
    /// which is what "Reset to Defaults" means: the chat ends up holding exactly the baseline,
    /// not a blend of the baseline and what was there before.
    public mutating func replace(with other: SamplingConfig) {
        self = other
    }
}
