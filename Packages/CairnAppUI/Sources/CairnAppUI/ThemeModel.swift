import Foundation
import Observation
import SwiftUI
import CairnChatDomain

/// The app-wide settings object: the theme, the appearance, and the Default Configuration every new
/// chat is seeded from.
///
/// Views reach settings only through this object, because `CairnAppUI` may not import SwiftData. It
/// holds the whole `AppSettings` value rather than one property per control: settings are written
/// whole, so a default configuration can never be saved without the theme that was edited beside it.
@Observable @MainActor
public final class ThemeModel {
    public private(set) var settings: AppSettings
    public var lastError: String?

    /// The paint this app's windows wear, as one narrowly-tracked value.
    ///
    /// Views resolve their colours through this rather than through `settings`, because a settings write
    /// that moves neither the theme nor the appearance must not repaint the route and every presentation
    /// hanging off it. See `ThemeChrome` for why reading the paint off the settings value is the wrong
    /// shape, and `ThemeChrome.swift` for the rule that decides when this one moves.
    ///
    /// `internal(set)`, not `private(set)`: the rule that decides when it moves lives in its own file, and
    /// Swift makes a `private` setter visible only to the file that declared it.
    public internal(set) var chrome: ThemeChrome

    /// The two tool-registry answers, as one value that moves only when one of them moves. Held so the
    /// launch view can watch it without depending on every settings write in the app.
    public internal(set) var toolSignals: ToolSignals

    private let storing: (any AppSettingsStoring)?

    /// The live object, reading through the store. A store that fails to read leaves the shipped
    /// defaults in place rather than leaving the app with no settings at all.
    public init(storing: any AppSettingsStoring) {
        self.storing = storing
        let read = (try? storing.appSettings()) ?? .default
        self.settings = read
        self.chrome = Self.resolvedChrome(for: read)
        self.toolSignals = Self.resolvedSignals(for: read)
    }

    /// Previews and tests, with nothing behind them. Writes here are kept in memory only.
    public init(settings: AppSettings = .default) {
        self.storing = nil
        self.settings = settings
        self.chrome = Self.resolvedChrome(for: settings)
        self.toolSignals = Self.resolvedSignals(for: settings)
    }

    /// The theme, resolved through the provider so there is one path from a stored id to paint.
    public var palette: CairnPalette { chrome.palette }

    /// Which half of the system appearance to pin. `nil` for "follow the device", which is what
    /// `.preferredColorScheme` needs to be handed in order to not override anything.
    ///
    /// Read from `chrome` and not from `settings`, for the same reason as `palette`: this is asked by the
    /// root window, and reading the settings value here would make every settings write in the app — a
    /// download acknowledgement, a provider's consent — invalidate the window that owns every presentation.
    public var colorScheme: ColorScheme? { ThemeProvider.pinnedScheme(chrome.appearance) }

    /// The colours to draw with, given what the device is showing right now. Views that need the
    /// device's own appearance pass it in; `cairnChrome` does this from the environment.
    public func tokens(deviceScheme: ColorScheme) -> CairnThemeTokens {
        ThemeProvider.tokens(
            themeID: settings.themeID,
            appearance: settings.appearance,
            deviceScheme: deviceScheme
        )
    }

    public func select(themeID: String) { mutate { $0.themeID = themeID } }
    public func select(appearance: AppearanceMode) { mutate { $0.appearance = appearance } }

    /// The Default Configuration for new chats. Existing chats keep what they were seeded with —
    /// `ChatWorkspace` copies the baseline in at creation and never re-resolves it.
    public func saveDefaultConfig(_ config: ChatConfig) {
        mutate { $0.defaultChatConfig = config }
    }

    public func setShowsGenerationStats(_ shows: Bool) {
        mutate { $0.showsGenerationStats = shows }
    }

    /// The outbound web acknowledgement, granted from Settings or from the composer's first-use
    /// disclosure. It goes through the one settings row like every other switch here, so the
    /// acknowledgement survives a relaunch instead of being re-asked — or silently forgotten.
    public func setOutboundWebAllowed(_ allowed: Bool) {
        mutate { $0.setOutboundWebAllowed(allowed) }
    }

    /// Whether the Model Manager's Download tab shows the curated library. A preference, not a
    /// permission: it defaults to on, and turning it off changes what a screen shows rather than what
    /// the device is allowed to send.
    ///
    /// `= $0.…`, and not a bare `$0.…`. This domain setter returns a **new** settings value rather than
    /// mutating in place — the stored key is optional and the whole copy is what goes to the store — so a
    /// bare call hands the result to `@discardableResult`, which drops it legally and silently, and nothing
    /// is written. The line beside it, `setShowsGenerationStats`, is a mutating setter, which is why one
    /// shape looks correct for both and only one of them is.
    ///
    /// The bug this note is about was the other one of these two: `setModelDownloadsAllowed` was written
    /// in the bare form, so the acknowledgement was granted on screen and never in the record. The tap
    /// started nothing, the Download tab printed its notice line, and that line appearing inside the list's
    /// own content dismissed the sheet the person was standing in.
    public func setDownloadCatalogShown(_ shown: Bool) {
        mutate { $0 = $0.setDownloadCatalogShown(shown) }
    }

    /// The acknowledgement for pulling model weights. Off until granted, and read through the settings
    /// value by anything that is about to start a download rather than cached in a view.
    ///
    /// Takes the returned copy for the reason given on `setDownloadCatalogShown` — this is the
    /// copy-returning shape, and the bare form silently wrote nothing. `Tests/CairnTests` proves the write
    /// lands, in memory and through the store, because no compiler error was ever going to catch it.
    public func setModelDownloadsAllowed(_ allowed: Bool) {
        mutate { $0 = $0.setModelDownloadsAllowed(allowed) }
    }

    /// The user's own SearXNG endpoint and the whole web-search surface — providers, selection, result
    /// count, the per-provider consent answers and the page-read answer — live in
    /// `ThemeModel+WebSearch.swift`, because they are one group of rows that a settings screen writes and
    /// a tool reads, and this file was carrying two subjects' worth of documentation.

    public func save(_ updated: AppSettings) { mutate { $0 = updated } }

    public func reload() {
        guard let storing else { return }
        do {
            settings = try storing.appSettings()
            republish(from: settings)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The one path every settings write goes through: copy, change, publish, save.
    ///
    /// `internal`, not `private`: the web-search rows live in `ThemeModel+WebSearch.swift`, and Swift
    /// makes a `private` member visible only to the file that declared it. They still go through this
    /// method, so nothing writes settings around the store.
    func mutate(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        settings = updated
        // The derived values move with the settings value they were read from — and only when the half a
        // window paints with actually moved. See `republish(from:)` in `ThemeChrome.swift`.
        republish(from: updated)
        guard let storing else { return }
        do {
            try storing.saveAppSettings(updated)
            lastError = nil
        } catch {
            // Typed message from the store; settings text is never prompt content.
            lastError = error.localizedDescription
        }
    }
}
