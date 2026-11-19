import SwiftUI
import CairnChatDomain

/// The one rule that decides what a Cairn window is painted with.
///
/// Root, sheet, and every stack pushed inside either all have to agree, and they can only agree if they
/// read the same function. Each screen used to resolve its own: the root read the stored theme, and every
/// presentation that forgot to do the same fell back to the environment default, which is the dark half
/// of one theme — so choosing an accent and a light appearance recoloured the transcript and left every
/// sheet, menu and nav bar in the old palette. The complaint on the phone was that the theme "does not
/// propagate"; this type is the single answer to "with what?".
///
/// A theme changes paint only. It never influences where a prompt goes or whether a request is
/// encrypted — that is `NetworkClass`'s job, and nothing here reads it.
@MainActor
public enum CairnChromeStyle {
    /// The shipped identity, for a window with no settings object wired: previews, tests, and a root
    /// whose store has not resolved yet.
    public static var fallback: CairnPalette { CairnPalette.trailhead }

    /// The theme in use, or the shipped identity when nothing is wired.
    public static func palette(for theme: ThemeModel?) -> CairnPalette {
        theme?.palette ?? fallback
    }

    /// Light, dark, or the device — the second, independent half of the choice.
    public static func appearance(for theme: ThemeModel?) -> AppearanceMode {
        theme?.settings.appearance ?? .system
    }

    /// The half to paint with: the pinned appearance if the user pinned one, otherwise the device.
    public static func resolveScheme(
        for theme: ThemeModel?,
        deviceScheme: ColorScheme
    ) -> ColorScheme {
        ThemeProvider.resolveScheme(appearance: appearance(for: theme), deviceScheme: deviceScheme)
    }

    public static func tokens(for theme: ThemeModel?, deviceScheme: ColorScheme) -> CairnThemeTokens {
        palette(for: theme).tokens(for: resolveScheme(for: theme, deviceScheme: deviceScheme))
    }

    /// The scheme to pin at window level — `nil` for "follow the device", which overrides nothing.
    public static func pinnedScheme(for theme: ThemeModel?) -> ColorScheme? {
        ThemeProvider.pinnedScheme(appearance(for: theme))
    }
}
