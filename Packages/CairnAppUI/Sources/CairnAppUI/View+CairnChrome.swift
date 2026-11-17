import SwiftUI
import CairnChatDomain

/// Paints a screen with the chosen palette.
///
/// Kept as one modifier so the root view and every sheet apply the same thing; a sheet that forgets the
/// scheme would sit in the old appearance beside a recoloured app, which reads as a bug in the theme
/// rather than a missed line of code.
public extension View {
    func cairnChrome(_ palette: CairnPalette, scheme: ColorScheme? = nil) -> some View {
        self
            .tint(palette.accent)
            .background(palette.canvas)
            .preferredColorScheme(scheme)
    }
}
