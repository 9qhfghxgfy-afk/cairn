import SwiftUI
import CairnChatDomain

/// A named theme: one identity, two variants.
///
/// Every theme carries a light half and a dark half, and `ThemeProvider` picks one from the user's
/// `AppearanceMode` plus the device's own setting. A theme therefore never decides which appearance
/// the app runs in — that is the user's appearance control in Settings, and the two stay separate
/// choices on purpose, because "I want Quartz" and "it is night" are different decisions.
///
/// This is *chrome*, not a rewrite of every colour in the app: `CairnTheme` still carries the marks,
/// badges and status colours that must stay fixed so that "amber means this kind of traffic" does not
/// change with a theme. What a theme owns is the surface, the accent, and the two message bubbles.
///
/// Not `Sendable`: a theme holds `Color`, and paint belongs on the main actor.
public struct CairnPalette: Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let note: String
    public let light: CairnThemeTokens
    public let dark: CairnThemeTokens

    public init(
        id: String,
        displayName: String,
        note: String,
        light: CairnThemeTokens,
        dark: CairnThemeTokens
    ) {
        self.id = id
        self.displayName = displayName
        self.note = note
        self.light = light
        self.dark = dark
    }

    /// The half to paint with.
    public func tokens(for scheme: ColorScheme) -> CairnThemeTokens {
        scheme == .dark ? dark : light
    }
}
