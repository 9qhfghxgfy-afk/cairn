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
    /// Whether the Download tab shows the curated library. Optional so a row written before the screen
    /// existed reads as "never answered" and takes the shipped answer — on — instead of a column default
    /// that silently restates a preference nobody set.
    public var showsDownloadCatalog: Bool?
    /// The acknowledgement for pulling model weights. Optional, and read as **not granted** when unset:
    /// a row that never granted it has not agreed to the traffic.
    public var modelDownloadsAllowed: Bool?
    public var updatedAt: Date
    /// The outbound web acknowledgement. A switch the user granted once, and a switch that is not stored is
    /// a switch that either re-asks forever or silently stops working.
    public var outboundWebAllowed: Bool?
    /// The **legacy** single SearXNG address, kept so an upgrade can import it into a provider row.
    public var searxngURL: String?
    /// The provider list, active selection, result count and per-provider consent, as one blob.
    ///
    /// Before this column none of it was stored at all: `toSettings()` built `AppSettings` without
    /// `webTools`, so the acknowledgement and the search address were gone on every relaunch. Every new
    /// attribute here is optional, which is what lets an existing store migrate by itself.
    public var webSearchJSON: Data?

    public init(
        slot: Int = 0,
        defaultConfigJSON: Data? = nil,
        themeID: String? = nil,
        appearanceRaw: String? = nil,
        showsGenerationStats: Bool? = nil,
        updatedAt: Date = Date(),
        outboundWebAllowed: Bool? = nil,
        searxngURL: String? = nil,
        webSearchJSON: Data? = nil,
        showsDownloadCatalog: Bool? = nil,
        modelDownloadsAllowed: Bool? = nil
    ) {
        self.slot = slot
        self.defaultConfigJSON = defaultConfigJSON
        self.themeID = themeID
        self.appearanceRaw = appearanceRaw
        self.showsGenerationStats = showsGenerationStats
        self.updatedAt = updatedAt
        self.outboundWebAllowed = outboundWebAllowed
        self.searxngURL = searxngURL
        self.webSearchJSON = webSearchJSON
        self.showsDownloadCatalog = showsDownloadCatalog
        self.modelDownloadsAllowed = modelDownloadsAllowed
    }
}

extension SettingsRecord {
    /// Missing columns read as the shipped defaults rather than as "off" or "blank": a row written
    /// by an older build must not silently disable something the user never disabled.
    func toSettings() -> AppSettings {
        var search = JSONCodec.decode(WebSearchSettings.self, from: webSearchJSON) ?? .default
        // A row written before providers existed holds one loose SearXNG address. Importing it here rather
        // than at launch means the first read after an upgrade already has the provider row, and the next
        // write stores it — so there is no window in which an instance the user was already searching
        // through stops working. The import is skipped once the column exists, which makes it idempotent.
        if webSearchJSON == nil {
            WebSearchMigration.importLegacySearxngURL(searxngURL, into: &search)
        }
        return AppSettings(
            defaultChatConfig: JSONCodec.decode(ChatConfig.self, from: defaultConfigJSON) ?? .default,
            themeID: themeID.flatMap { $0.isEmpty ? nil : $0 } ?? AppSettings.defaultThemeID,
            appearance: AppearanceMode(rawValue: appearanceRaw ?? "") ?? .system,
            showsGenerationStats: showsGenerationStats ?? true,
            webTools: WebToolSettings(
                outboundAllowed: outboundWebAllowed ?? false,
                searxngURL: searxngURL,
                search: search
            ),
            // Both pass through as stored, including `nil`: the accessors on `AppSettings` are what turn
            // "never answered" into the shipped answer, and one of those answers is "not granted".
            showsDownloadCatalog: showsDownloadCatalog,
            modelDownloadsAllowed: modelDownloadsAllowed
        )
    }

    func apply(_ settings: AppSettings, now: Date) {
        defaultConfigJSON = JSONCodec.encode(settings.defaultChatConfig)
        themeID = settings.themeID
        appearanceRaw = settings.appearance.rawValue
        showsGenerationStats = settings.showsGenerationStats
        let tools = settings.webTools ?? .default
        outboundWebAllowed = tools.outboundAllowed
        // Written back as-is so the legacy field cannot be resurrected after it has been cleared at its
        // source.
        searxngURL = tools.searxngURL
        // Only written once there is something to write. A settings value that still carries `nil` here is
        // a build that has never touched the provider list, and that is exactly the state the import in
        // `toSettings()` keys off — writing a default blob here would erase the signal and lose an existing
        // SearXNG address instead of importing it.
        webSearchJSON = tools.search.flatMap { JSONCodec.encode($0) }
        showsDownloadCatalog = settings.showsDownloadCatalog
        modelDownloadsAllowed = settings.modelDownloadsAllowed
        updatedAt = now
    }
}
