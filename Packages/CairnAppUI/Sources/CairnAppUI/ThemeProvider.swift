import SwiftUI
import CairnChatDomain

/// Decides which theme, and which half of it, the app paints with.
///
/// Two independent inputs, and keeping them independent is the whole point: `themeID` is *which
/// identity* the user wants, `AppearanceMode` is *whether the app should be light or dark*. An older
/// build coupled them — a theme pinned its own appearance, so choosing "Quartz" also silently chose
/// "light" and overrode the device. Now a theme supplies both halves and the mode picks one, which
/// means every theme is usable at 3 a.m. and at noon.
///
/// A theme changes paint only. It never influences where a prompt goes, which server is reachable, or
/// whether a request is encrypted — that is `NetworkClass`'s job, and nothing in this file reads it.
@MainActor
public enum ThemeProvider {
    /// The themes offered in Settings, in display order.
    public static var themes: [CairnPalette] { CairnPalette.all }

    /// The theme for a stored id, falling back to the shipped identity.
    public static func theme(id: String) -> CairnPalette { CairnPalette.palette(id: id) }

    /// The appearance to pin, or `nil` to follow the device. `nil` is what
    /// `.preferredColorScheme` needs to be handed in order to override nothing.
    public static func pinnedScheme(_ appearance: AppearanceMode) -> ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The half to paint with: the pinned one if the user pinned an appearance, otherwise whatever the
    /// device is showing. The device scheme is passed in rather than read from a global, so a test can
    /// ask the same question for both halves without touching the system settings.
    public static func resolveScheme(
        appearance: AppearanceMode,
        deviceScheme: ColorScheme
    ) -> ColorScheme {
        pinnedScheme(appearance) ?? deviceScheme
    }

    /// The colours to draw with, for a stored theme id and an appearance.
    public static func tokens(
        themeID: String,
        appearance: AppearanceMode,
        deviceScheme: ColorScheme
    ) -> CairnThemeTokens {
        theme(id: themeID).tokens(for: resolveScheme(appearance: appearance, deviceScheme: deviceScheme))
    }
}
