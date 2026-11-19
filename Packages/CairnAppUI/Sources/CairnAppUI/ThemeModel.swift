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

    private let storing: (any AppSettingsStoring)?

    /// The live object, reading through the store. A store that fails to read leaves the shipped
    /// defaults in place rather than leaving the app with no settings at all.
    public init(storing: any AppSettingsStoring) {
        self.storing = storing
        self.settings = (try? storing.appSettings()) ?? .default
    }

    /// Previews and tests, with nothing behind them. Writes here are kept in memory only.
    public init(settings: AppSettings = .default) {
        self.storing = nil
        self.settings = settings
    }

    /// The theme, resolved through the provider so there is one path from a stored id to paint.
    public var palette: CairnPalette { ThemeProvider.theme(id: settings.themeID) }

    /// Which half of the system appearance to pin. `nil` for "follow the device", which is what
    /// `.preferredColorScheme` needs to be handed in order to not override anything.
    public var colorScheme: ColorScheme? { ThemeProvider.pinnedScheme(settings.appearance) }

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

    /// The user's own SearXNG endpoint; nil or empty means "not set", which is what makes the keyless
    /// default the answer instead of a broken address.
    ///
    /// **Legacy**, kept while the import that turns it into a provider row still has to run on installs that
    /// predate providers. New code writes `setWebSearch`.
    public func setSearXNGURL(_ url: String?) {
        mutate { $0.setSearXNGURL(url) }
    }

    /// The whole web-search settings value, written as one unit.
    ///
    /// Providers, selection, result count and consent travel together because a provider list saved without
    /// its consent record would be a list that can search somewhere the user never agreed to.
    public func setWebSearch(_ search: WebSearchSettings) {
        mutate { $0.setWebSearch(search) }
    }

    /// Selecting a provider, and clearing the notice that says selection moved. Both go through the store so
    /// a row the user tapped cannot be ignored, and a notice cannot outlive the choice it describes.
    public func selectWebSearchProvider(id: UUID) {
        mutate { $0.selectWebSearchProvider(id: id) }
    }

    public func setWebSearchResultCount(_ count: Int) {
        mutate { $0.setWebSearchResultCount(count) }
    }

    /// The per-provider answer to the outbound question: granted, or declined and remembered.
    public func grantWebSearchConsent(for profile: WebSearchProviderProfile) {
        mutate { $0.grantWebSearchConsent(for: profile) }
    }

    public func denyWebSearchConsent(for profile: WebSearchProviderProfile) {
        mutate { $0.denyWebSearchConsent(for: profile) }
    }

    public func save(_ updated: AppSettings) { mutate { $0 = updated } }

    public func reload() {
        guard let storing else { return }
        do {
            settings = try storing.appSettings()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func mutate(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        settings = updated
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
