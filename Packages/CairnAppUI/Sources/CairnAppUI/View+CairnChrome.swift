import SwiftUI
import CairnChatDomain

/// Paints a screen with the chosen theme, in the right half of it.
///
/// Kept as one modifier so the root view and every sheet apply the same thing: a sheet that forgets it
/// would sit in the old appearance beside a recoloured app, which reads as a bug in the theme rather
/// than a missed line of code.
///
/// It is a wrapper view rather than a chain of modifiers because it has to *read* the device's
/// appearance from the environment before choosing which half of the theme to paint with — something a
/// plain `View` extension cannot do.
public extension View {
    func cairnChrome(
        _ palette: CairnPalette,
        appearance: AppearanceMode = .system
    ) -> some View {
        CairnChrome(content: self, palette: palette, appearance: appearance)
    }
}

private struct CairnChrome<Content: View>: View {
    @Environment(\.colorScheme) private var deviceScheme
    private let content: Content
    private let palette: CairnPalette
    private let appearance: AppearanceMode

    init(content: Content, palette: CairnPalette, appearance: AppearanceMode) {
        self.content = content
        self.palette = palette
        self.appearance = appearance
    }

    var body: some View {
        let tokens = palette.tokens(
            for: ThemeProvider.resolveScheme(appearance: appearance, deviceScheme: deviceScheme)
        )
        content
            .tint(tokens.accent)
            .environment(\.cairnTokens, tokens)
            .background(tokens.canvas)
            // `nil` for "match the device": passing nil overrides nothing, which is the point.
            .preferredColorScheme(ThemeProvider.pinnedScheme(appearance))
    }
}
