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
        modifier(CairnChromeModifier(palette: palette, appearance: appearance))
    }

    /// Paints with the app's live theme, so a theme change repaints this window without every screen
    /// having to know the palette's name.
    func cairnChrome(theme: ThemeModel?) -> some View {
        modifier(
            CairnChromeModifier(
                palette: CairnChromeStyle.palette(for: theme),
                appearance: CairnChromeStyle.appearance(for: theme)
            )
        )
    }

    /// Paints a presentation with the theme it was presented from.
    ///
    /// A sheet arrives with an environment of its own, so a window presented from a tinted root is not
    /// tinted by it; `theme` carries the choice across that gap. With no theme handed in, the paint the
    /// environment already carries is kept, which is the right answer for a stack pushed inside a sheet.
    func cairnPresentation(theme: ThemeModel? = nil) -> some View {
        guard let theme else {
            return modifier(CairnChromeModifier(palette: nil, appearance: nil))
        }
        return modifier(
            CairnChromeModifier(
                palette: CairnChromeStyle.palette(for: theme),
                appearance: CairnChromeStyle.appearance(for: theme)
            )
        )
    }
}

/// The paint rule for one Cairn window, expressed as a modifier rather than a chain.
///
/// Everything is resolved **before** this type is built, and that ordering is not a style choice: a
/// `ViewModifier`'s `body(content:)` is not main-actor isolated in the iOS SDK, while the settings object
/// and `ThemeProvider` are, so a modifier that reached for them inside `body` is a Swift 6 concurrency
/// error. The `View` extension methods above run on the main actor and do the resolving; what is stored
/// here is a palette, an appearance, and the environment's own paint — values, none of them isolated.
struct CairnChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var deviceScheme
    @Environment(\.cairnTokens) private var presentedPaint

    /// The palette to paint with. `nil` keeps the paint this view was already presented with, which is
    /// what a screen pushed inside a themed sheet needs.
    let palette: CairnPalette?
    /// The appearance the user pinned. `nil` means "inherit the window's", which pins nothing.
    let appearance: AppearanceMode?

    /// The half of the palette to draw with: the pinned half when one is pinned, the device's otherwise.
    private var scheme: ColorScheme {
        switch appearance {
        case .none, .some(.system): return deviceScheme
        case .some(.light): return .light
        case .some(.dark): return .dark
        }
    }

    /// The scheme to pin at window level. `nil` overrides nothing — which is what "follow the device" has
    /// to mean inside a sheet's own window too, because a presentation inherits the window's pinning
    /// rather than adding a second one.
    private var pinnedScheme: ColorScheme? {
        switch appearance {
        case .none, .some(.system): return nil
        case .some(.light): return .light
        case .some(.dark): return .dark
        }
    }

    /// The colours to draw with: the resolved half of the palette, or the paint handed down by the
    /// presentation above when no palette was given. `CairnPalette` is a plain value type, so resolving
    /// it here is legal off the main actor; nothing in this type reads a store or a model.
    private var paint: CairnThemeTokens {
        guard let palette else { return presentedPaint }
        return palette.tokens(for: scheme)
    }

    func body(content: Content) -> some View {
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
            .preferredColorScheme(pinnedScheme)
    }
}
