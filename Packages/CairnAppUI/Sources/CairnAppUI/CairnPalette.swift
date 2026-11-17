import SwiftUI

/// A named set of chrome colours the user can pick in Settings.
///
/// This is deliberately a *chrome* palette, not a rewrite of every colour in the app: `CairnTheme`
/// still carries the marks, badges and status colours that must stay fixed so that "amber means this
/// kind of traffic" does not change with a theme. What a theme owns is the surface the app sits on and
/// the accent that actions take, plus which half of the system appearance it wants — which is what a
/// palette with a light half and a dark half actually needs to be selectable.
///
/// Not `Sendable`: a palette is a view-layer value handed to views on the main actor, and `Color` is
/// not a type worth promising to ship across threads.
public struct CairnPalette: Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let note: String
    /// Behind everything, including the transcript.
    public let canvas: Color
    /// Cards, the composer field, rows.
    public let surface: Color
    /// Actions, selection, the mark.
    public let accent: Color
    /// `nil` follows the device. A palette that only looks right one way pins it.
    public let scheme: ColorScheme?

    public init(
        id: String,
        displayName: String,
        note: String,
        canvas: Color,
        surface: Color,
        accent: Color,
        scheme: ColorScheme? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.note = note
        self.canvas = canvas
        self.surface = surface
        self.accent = accent
        self.scheme = scheme
    }
}

/// The built-in palettes. `@MainActor` because a palette holds `Color`, which is not `Sendable`: the
/// compiler will not let a non-Sendable value sit in a global `let`, and it is right — these are paint,
/// and paint belongs on the main actor. Every caller here is a view or a view model that already lives
/// there.
@MainActor
public extension CairnPalette {
    /// Cairn's original identity — the slate-and-amber the app shipped looking like.
    static let trailhead = CairnPalette(
        id: "trailhead",
        displayName: "Trailhead",
        note: "Slate and amber. The colours Cairn shipped with.",
        canvas: Color(red: 0.07, green: 0.08, blue: 0.10),
        surface: Color(red: 0.10, green: 0.12, blue: 0.15),
        accent: Color(red: 0.95, green: 0.69, blue: 0.28),
        scheme: .dark
    )

    static let dusk = CairnPalette(
        id: "dusk",
        displayName: "Dusk",
        note: "Green-grey, low contrast. Easier on the eyes at night.",
        canvas: Color(red: 0.06, green: 0.09, blue: 0.09),
        surface: Color(red: 0.11, green: 0.15, blue: 0.15),
        accent: Color(red: 0.49, green: 0.68, blue: 0.55),
        scheme: .dark
    )

    static let passage = CairnPalette(
        id: "passage",
        displayName: "Passage",
        note: "Warm paper. For using Cairn in daylight.",
        canvas: Color(red: 0.94, green: 0.93, blue: 0.90),
        surface: Color(red: 0.99, green: 0.99, blue: 0.98),
        accent: Color(red: 0.48, green: 0.33, blue: 0.16),
        scheme: .light
    )

    static let quartz = CairnPalette(
        id: "quartz",
        displayName: "Quartz",
        note: "Cool paper, blue accent.",
        canvas: Color(red: 0.93, green: 0.94, blue: 0.96),
        surface: Color(red: 0.99, green: 1.0, blue: 1.0),
        accent: Color(red: 0.22, green: 0.36, blue: 0.52),
        scheme: .light
    )

    static let all: [CairnPalette] = [.trailhead, .dusk, .passage, .quartz]

    /// The palette for a stored id, falling back to the shipped identity. A theme id from a newer
    /// build is not the user's mistake, and a settings row that could not resolve its own theme would
    /// leave the app with no colours at all.
    static func palette(id: String) -> CairnPalette {
        all.first { $0.id == id } ?? .trailhead
    }
}
