import SwiftUI
import CairnChatDomain

/// Paints a Cairn window with the chosen theme, in the right half of it.
///
/// Three entry points, one rule (`CairnChromeStyle`) behind all of them: a screen handed a palette paints
/// itself with it; a window handed the live theme paints itself from the settings object; and a
/// **presentation** — a sheet, or a stack pushed inside one — paints itself with whatever it was presented
/// from, read out of the environment when no theme is handed in.
///
/// It is a modifier that reads the environment rather than a chain of modifiers, because the half of the
/// theme to paint with is the device's appearance at the point of application, and because the navigation
/// bar has to be told the same thing the canvas was. A sheet that skipped this used to fall back to the
/// environment default — one fixed dark palette — which is why changing the accent and the appearance
/// moved the transcript and left every sheet, menu and bar behind.
public extension View {
    /// Paints with one palette, resolved at the point it is applied.
    func cairnChrome(
        _ palette: CairnPalette,
        appearance: AppearanceMode = .system
    ) -> some View {
        modifier(CairnChromeModifier(source: .palette(palette, appearance)))
    }

    /// Paints with the app's live theme, so a theme change repaints this window without every screen
    /// having to know the palette's name.
    func cairnChrome(theme: ThemeModel?) -> some View {
        modifier(CairnChromeModifier(source: .theme(theme)))
    }

    /// Paints a presentation with the theme it was presented from.
    ///
    /// A sheet arrives with an environment of its own, so a window presented from a tinted root is not
    /// tinted by it; `theme` carries the choice across that gap. With no theme handed in, the paint the
    /// environment already carries is kept, which is the right answer for a stack pushed inside a sheet.
    func cairnPresentation(theme: ThemeModel? = nil) -> some View {
        modifier(CairnChromeModifier(source: .inherited(theme)))
    }
}

/// Where a window's paint comes from. Internal: the three modifiers above are the whole surface.
enum CairnChromeSource {
    case palette(CairnPalette, AppearanceMode)
    case theme(ThemeModel?)
    /// A presentation. A theme given resolves it; no theme means "keep what I was presented with".
    case inherited(ThemeModel?)
}

/// The paint rule for one Cairn window, expressed as a modifier rather than a chain.
///
/// `@MainActor` sits on the two helpers rather than on the type: a type-level annotation would make the
/// memberwise initializer main-actor-isolated, and the `View` extension methods that call it are not
/// isolated, which is a Swift 6 error. The colours being resolved come from a `@MainActor` settings
/// object, so the resolution has to be main-actor work; the modifier itself needs no isolation.
struct CairnChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var deviceScheme
    @Environment(\.cairnTokens) private var inheritedTokens
    let source: CairnChromeSource

    func body(content: Content) -> some View {
        let paint = resolvedTokens()
        content
            .tint(paint.accent)
            .environment(\.cairnTokens, paint)
            .background(paint.canvas)
            // The bar is part of the window. Left alone it keeps the system's own material and the old
            // accent, which is the half of "the theme did not apply" a canvas background cannot reach.
            .toolbarBackground(paint.surface, for: .navigationBar)
            .toolbarColorScheme(paint.isDark ? .dark : .light, for: .navigationBar)
            // The sheet's own material, so a presented window does not sit on the system's card colour
            // beside a themed canvas. A no-op anywhere that is not a presentation.
            .presentationBackground(paint.canvas)
            // `nil` for "match the device": passing nil overrides nothing, which is the point.
            .preferredColorScheme(pinnedScheme())
    }

    @MainActor
    private func resolvedTokens() -> CairnThemeTokens {
        switch source {
        case .palette(let palette, let appearance):
            return palette.tokens(
                for: ThemeProvider.resolveScheme(appearance: appearance, deviceScheme: deviceScheme)
            )
        case .theme(let theme):
            return CairnChromeStyle.tokens(for: theme, deviceScheme: deviceScheme)
        case .inherited(let theme):
            guard let theme else { return inheritedTokens }
            return CairnChromeStyle.tokens(for: theme, deviceScheme: deviceScheme)
        }
    }

    @MainActor
    private func pinnedScheme() -> ColorScheme? {
        switch source {
        case .palette(_, let appearance):
            return ThemeProvider.pinnedScheme(appearance)
        case .theme(let theme), .inherited(let theme):
            return CairnChromeStyle.pinnedScheme(for: theme)
        }
    }
}
