import SwiftUI

/// The built-in themes. Each is written twice — a light half and a dark half — because every theme
/// has to survive the device going dark at sunset and coming back at noon without the user having to
/// change anything but the appearance.
///
/// These are computed rather than stored. A stored global of a non-`Sendable` type is shared mutable
/// state under Swift 6's rules, and a colour set is neither; a computed property is just a recipe, so
/// it can be read from anywhere, including the environment default.
///
/// Every name here is Cairn's own. No palette, colour value, or note is taken from another app.
public extension CairnPalette {
    /// Cairn's original identity — slate and amber, the colours the app shipped looking like.
    static var trailhead: CairnPalette {
        CairnPalette(
            id: "trailhead",
            displayName: "Trailhead",
            note: "Slate and amber. The colours Cairn shipped with.",
            light: CairnThemeTokens(
                canvas: Color(red: 0.93, green: 0.94, blue: 0.95),
                surface: Color(red: 1.0, green: 1.0, blue: 1.0),
                accent: Color(red: 0.62, green: 0.42, blue: 0.13),
                userBubble: Color(red: 0.95, green: 0.90, blue: 0.80),
                assistantBubble: Color(red: 1.0, green: 1.0, blue: 1.0),
                onCanvas: Color(red: 0.10, green: 0.12, blue: 0.15),
                onCanvasMuted: Color(red: 0.38, green: 0.42, blue: 0.47),
                isDark: false
            ),
            dark: CairnThemeTokens.trailheadDark
        )
    }

    /// Green-grey and low contrast — the one to use in a dark room.
    static var dusk: CairnPalette {
        CairnPalette(
            id: "dusk",
            displayName: "Dusk",
            note: "Green-grey, low contrast. Easier on the eyes at night.",
            light: CairnThemeTokens(
                canvas: Color(red: 0.91, green: 0.93, blue: 0.92),
                surface: Color(red: 0.99, green: 1.0, blue: 0.99),
                accent: Color(red: 0.24, green: 0.44, blue: 0.33),
                userBubble: Color(red: 0.84, green: 0.90, blue: 0.87),
                assistantBubble: Color(red: 0.99, green: 1.0, blue: 0.99),
                onCanvas: Color(red: 0.09, green: 0.13, blue: 0.12),
                onCanvasMuted: Color(red: 0.33, green: 0.38, blue: 0.36),
                isDark: false
            ),
            dark: CairnThemeTokens(
                canvas: Color(red: 0.06, green: 0.09, blue: 0.09),
                surface: Color(red: 0.11, green: 0.15, blue: 0.15),
                accent: Color(red: 0.49, green: 0.68, blue: 0.55),
                userBubble: Color(red: 0.18, green: 0.24, blue: 0.23),
                assistantBubble: Color(red: 0.11, green: 0.15, blue: 0.15),
                onCanvas: .white,
                onCanvasMuted: Color(red: 0.60, green: 0.66, blue: 0.64),
                isDark: true
            )
        )
    }
    /// The order the Settings picker lists them in, original identity first.
    static var all: [CairnPalette] { [.trailhead, .dusk, .passage, .quartz] }

    /// The theme for a stored id, falling back to the shipped identity. A theme id from a newer
    /// build is not the user's mistake, and a settings row that could not resolve its own theme would
    /// leave the app with no colours at all.
    static func palette(id: String) -> CairnPalette {
        all.first { $0.id == id } ?? .trailhead
    }
}

/// The two light-first themes. Split from `CairnPalette+BuiltIn` only to keep each file short and
/// single-purpose; `all` above is still the one list, and every theme here still carries both halves.
public extension CairnPalette {
    /// Warm paper with a bark-brown accent — for using Cairn outdoors.
    static var passage: CairnPalette {
        CairnPalette(
            id: "passage",
            displayName: "Passage",
            note: "Warm paper. For using Cairn in daylight.",
            light: CairnThemeTokens(
                canvas: Color(red: 0.94, green: 0.93, blue: 0.90),
                surface: Color(red: 0.99, green: 0.99, blue: 0.98),
                accent: Color(red: 0.48, green: 0.33, blue: 0.16),
                userBubble: Color(red: 0.96, green: 0.92, blue: 0.85),
                assistantBubble: Color(red: 1.0, green: 1.0, blue: 1.0),
                onCanvas: Color(red: 0.13, green: 0.12, blue: 0.10),
                onCanvasMuted: Color(red: 0.40, green: 0.38, blue: 0.34),
                isDark: false
            ),
            dark: CairnThemeTokens(
                canvas: Color(red: 0.09, green: 0.08, blue: 0.07),
                surface: Color(red: 0.13, green: 0.12, blue: 0.11),
                accent: Color(red: 0.86, green: 0.66, blue: 0.42),
                userBubble: Color(red: 0.24, green: 0.21, blue: 0.18),
                assistantBubble: Color(red: 0.13, green: 0.12, blue: 0.11),
                onCanvas: Color(red: 0.95, green: 0.93, blue: 0.90),
                onCanvasMuted: Color(red: 0.66, green: 0.63, blue: 0.58),
                isDark: true
            )
        )
    }

    /// Cool paper with a slate-blue accent.
    static var quartz: CairnPalette {
        CairnPalette(
            id: "quartz",
            displayName: "Quartz",
            note: "Cool paper, blue accent.",
            light: CairnThemeTokens(
                canvas: Color(red: 0.93, green: 0.94, blue: 0.96),
                surface: Color(red: 0.99, green: 1.0, blue: 1.0),
                accent: Color(red: 0.22, green: 0.36, blue: 0.52),
                userBubble: Color(red: 0.86, green: 0.90, blue: 0.95),
                assistantBubble: Color(red: 1.0, green: 1.0, blue: 1.0),
                onCanvas: Color(red: 0.10, green: 0.12, blue: 0.15),
                onCanvasMuted: Color(red: 0.35, green: 0.40, blue: 0.46),
                isDark: false
            ),
            dark: CairnThemeTokens(
                canvas: Color(red: 0.06, green: 0.08, blue: 0.11),
                surface: Color(red: 0.10, green: 0.13, blue: 0.17),
                accent: Color(red: 0.55, green: 0.72, blue: 0.88),
                userBubble: Color(red: 0.19, green: 0.25, blue: 0.33),
                assistantBubble: Color(red: 0.10, green: 0.13, blue: 0.17),
                onCanvas: .white,
                onCanvasMuted: Color(red: 0.60, green: 0.65, blue: 0.71),
                isDark: true
            )
        )
    }
}
