import Foundation
import SwiftData
import CairnChatDomain

/// On-disk shape of the app-wide settings: the default chat configuration, the theme, the
/// appearance, and the statistics preference.
///
/// One singleton row, like `ServerSelectionRecord`. These four things are read and written together
/// as one `AppSettings` value, and a row per key would let a half-written state survive a crash —
/// a default configuration that disagrees with the theme that was being edited beside it.
///
/// Nothing here is secret. A theme id, an appearance choice, and a set of sampling knobs describe
/// how the user wants answers to be shaped; all of it stays on the device.
@Model
public final class SettingsRecord {
    /// Unique so a bug cannot create a second "the settings" row.
    @Attribute(.unique) public var slot: Int
    /// nil means the user has never touched the defaults, which is not the same as an empty
    /// configuration blob: "never set" and "set to nothing" must read back differently.
    public var defaultConfigJSON: Data?
    public var themeID: String?
    public var appearanceRaw: String?
    public var showsGenerationStats: Bool?
    public var updatedAt: Date

    public init(
        slot: Int = 0,
        defaultConfigJSON: Data? = nil,
        themeID: String? = nil,
        appearanceRaw: String? = nil,
        showsGenerationStats: Bool? = nil,
        updatedAt: Date = Date()
    ) {
        self.slot = slot
        self.defaultConfigJSON = defaultConfigJSON
        self.themeID = themeID
        self.appearanceRaw = appearanceRaw
        self.showsGenerationStats = showsGenerationStats
        self.updatedAt = updatedAt
    }
}

extension SettingsRecord {
    /// Missing columns read as the shipped defaults rather than as "off" or "blank": a row written
    /// by an older build must not silently disable something the user never disabled.
    func toSettings() -> AppSettings {
        AppSettings(
            defaultChatConfig: JSONCodec.decode(ChatConfig.self, from: defaultConfigJSON) ?? .default,
            themeID: themeID.flatMap { $0.isEmpty ? nil : $0 } ?? AppSettings.defaultThemeID,
            appearance: AppearanceMode(rawValue: appearanceRaw ?? "") ?? .system,
            showsGenerationStats: showsGenerationStats ?? true
        )
    }

    func apply(_ settings: AppSettings, now: Date) {
        defaultConfigJSON = JSONCodec.encode(settings.defaultChatConfig)
        themeID = settings.themeID
        appearanceRaw = settings.appearance.rawValue
        showsGenerationStats = settings.showsGenerationStats
        updatedAt = now
    }
}
