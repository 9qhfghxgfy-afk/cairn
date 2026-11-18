import Foundation

/// App-wide settings that are not about any one chat.
///
/// `defaultChatConfig` is the baseline a **new** chat is seeded from. It is a copy, not a live link:
/// changing the defaults later does not rewrite chats that already exist, because a conversation's
/// own settings are the user's, and silently re-resolving them would change answers in a chat they
/// are reading.
public struct AppSettings: Sendable, Equatable, Codable {
    public var defaultChatConfig: ChatConfig
    public var themeID: String
    public var appearance: AppearanceMode
    public var showsGenerationStats: Bool
    /// The web-tool switches, held as **one optional struct** rather than as loose keys. That shape is
    /// what keeps a settings blob written before P3 readable: a synthesized decoder reads a missing
    /// optional key as nil, while a missing non-optional `Bool` would fail the whole row and drop the
    /// user's theme and default configuration on the floor. Absent means the shipped answer — no
    /// outbound web tools, no self-hosted search endpoint.
    public var webTools: WebToolSettings?

    public init(
        defaultChatConfig: ChatConfig = .default,
        themeID: String = AppSettings.defaultThemeID,
        appearance: AppearanceMode = .system,
        showsGenerationStats: Bool = true,
        webTools: WebToolSettings? = nil
    ) {
        self.defaultChatConfig = defaultChatConfig
        self.themeID = themeID
        self.appearance = appearance
        self.showsGenerationStats = showsGenerationStats
        self.webTools = webTools
    }

    /// The palette that matches Cairn's original identity, and the fallback for any stored id this
    /// build does not know.
    public static let defaultThemeID = "trailhead"

    public static let `default` = AppSettings()

    /// The "N options configured" badge in Settings. Same rule as the per-chat count: sampling knobs
    /// the baseline explicitly asserts.
    public var configuredOptionCount: Int { defaultChatConfig.configuredOptionCount }

    public var hasConfiguredDefaults: Bool { configuredOptionCount > 0 }
}
