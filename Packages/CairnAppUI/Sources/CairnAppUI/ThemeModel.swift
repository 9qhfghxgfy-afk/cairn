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

    public var palette: CairnPalette { CairnPalette.palette(id: settings.themeID) }

    /// Which half of the system appearance to pin. `nil` for "follow the device", which is what
    /// `.preferredColorScheme` needs to be handed in order to not override anything.
    public var colorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
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
