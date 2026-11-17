import SwiftUI
import CairnChatDomain

/// The colours of one **variant** of one theme — the light half or the dark half.
///
/// A theme is not one colour set. Every Cairn theme ships both halves, because a theme that only
/// looks right in one appearance is a theme that fights the device: a user who sets their iPhone to
/// dark at sunset would have to change the theme, not the appearance, to keep reading. `ThemeProvider`
/// picks the half; this type is just the paint it hands to a view.
///
/// Not `Sendable`, and deliberately so: `Color` is not `Sendable`, and this is view-layer paint that
/// belongs on the main actor.
public struct CairnThemeTokens: Equatable {
    /// Behind everything, including the transcript.
    public let canvas: Color
    /// Cards, rows, the composer field.
    public let surface: Color
    /// Actions, selection, the mark, the user's own bubble.
    public let accent: Color
    /// The bubble the user's own words sit in.
    public let userBubble: Color
    /// The bubble the model's answer sits in.
    public let assistantBubble: Color
    /// Full-strength text on `canvas`.
    public let onCanvas: Color
    /// Secondary text: explainers, notes, captions.
    public let onCanvasMuted: Color
    /// True for the dark half. Drives nothing on its own; it is what a view needs to pick a
    /// system-shaped colour (a form background, a divider) that matches the half being painted.
    public let isDark: Bool

    public init(
        canvas: Color,
        surface: Color,
        accent: Color,
        userBubble: Color,
        assistantBubble: Color,
        onCanvas: Color,
        onCanvasMuted: Color,
        isDark: Bool
    ) {
        self.canvas = canvas
        self.surface = surface
        self.accent = accent
        self.userBubble = userBubble
        self.assistantBubble = assistantBubble
        self.onCanvas = onCanvas
        self.onCanvasMuted = onCanvasMuted
        self.isDark = isDark
    }

    /// The three colours that identify a theme at a glance, drawn as swatches.
    public var swatches: [Color] { [canvas, surface, accent] }
}

private struct CairnTokensKey: EnvironmentKey {
    /// The shipped identity's dark half, which is what Cairn looked like before themes existed — so a
    /// view built outside a themed window (a preview, a test host) renders the original way.
    static var defaultValue: CairnThemeTokens { CairnThemeTokens.trailheadDark }
}

public extension EnvironmentValues {
    /// The active theme's colours. Views read these instead of hard-coded constants, which is what
    /// makes "pick a theme" actually change the app rather than just the settings screen.
    var cairnTokens: CairnThemeTokens {
        get { self[CairnTokensKey.self] }
        set { self[CairnTokensKey.self] = newValue }
    }
}

public extension CairnThemeTokens {
    /// Cairn's original dark half, written from the same literals `CairnTheme` has always used. It is
    /// the environment default so an un-themed view still looks like Cairn, and it is what a fresh
    /// install shows before any theme is stored.
    static var trailheadDark: CairnThemeTokens {
        CairnThemeTokens(
            canvas: Color(red: 0.07, green: 0.08, blue: 0.10),
            surface: Color(red: 0.10, green: 0.12, blue: 0.15),
            accent: Color(red: 0.95, green: 0.69, blue: 0.28),
            userBubble: Color(red: 0.24, green: 0.27, blue: 0.31).opacity(0.55),
            assistantBubble: Color(red: 0.10, green: 0.12, blue: 0.15),
            onCanvas: .white,
            onCanvasMuted: Color(red: 0.62, green: 0.66, blue: 0.70),
            isDark: true
        )
    }
}
