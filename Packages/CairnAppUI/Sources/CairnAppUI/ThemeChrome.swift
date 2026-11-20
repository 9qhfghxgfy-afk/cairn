import CairnChatDomain

/// The paint a Cairn window wears, as one value.
///
/// This exists because Observation tracks a **property**, not a field inside a struct. A view that reads
/// `ThemeModel.settings` to work out its colours is therefore invalidated by *every* settings write in
/// the app, whether or not the write changed anything a person can see — and the views that read the
/// paint are the route view and every presentation, the ones holding the `.sheet` modifiers. That is the
/// churn behind a presentation stack collapsing when someone acknowledges model weights in a download
/// sheet: the acknowledgement is not a colour, but it was being read as one.
///
/// So the settings object resolves the paint once and republishes it only when the theme or the pinned
/// appearance actually moves. An unrelated preference then invalidates nothing outside Settings.
///
/// Not `Sendable`, and deliberately so: a palette holds `Color`, and paint belongs on the main actor —
/// which is also where this value lives.
public struct ThemeChrome: Equatable {
    public var palette: CairnPalette
    /// Light, dark, or the device. The second, independent half of the user's choice.
    public var appearance: AppearanceMode

    public init(palette: CairnPalette, appearance: AppearanceMode) {
        self.palette = palette
        self.appearance = appearance
    }
}

/// The two settings answers that decide which tools a chat gets, as one value that moves only when one
/// of them moves.
///
/// `CairnApp` watches this to re-assemble the tool registry. Watching `settings` instead would make the
/// launch view — the one that owns the store, the workspace, the theme and the root presentation —
/// depend on every settings write in the app, rebuilding the whole window chain to answer a question
/// about two switches.
public struct ToolSignals: Equatable, Sendable {
    /// The acknowledgement that lets a web tool's request leave the device.
    public var webToolsAllowed: Bool
    /// Whether a message shows the generation statistics row.
    public var showsGenerationStats: Bool

    public init(webToolsAllowed: Bool, showsGenerationStats: Bool) {
        self.webToolsAllowed = webToolsAllowed
        self.showsGenerationStats = showsGenerationStats
    }
}

/// The half of the settings object that is derived rather than chosen, and the rule for when it moves.
///
/// Kept with the two values it produces because they answer one question — *what may a window be
/// invalidated by* — while the settings object's own file answers a different one: *what has the user
/// chosen*. Conflating them is what makes the first question impossible to see.
extension ThemeModel {
    /// The paint implied by a settings value, through the same provider every theme lookup goes by.
    static func resolvedChrome(for settings: AppSettings) -> ThemeChrome {
        ThemeChrome(
            palette: ThemeProvider.theme(id: settings.themeID),
            appearance: settings.appearance
        )
    }

    /// The tool-registry answers implied by a settings value. `showsGenerationStats` belongs here because
    /// `ChatSessionModel` reads it into its generation-statistics flag at construction, so a change to it
    /// has to re-assemble the registry the same way the outbound acknowledgement does.
    static func resolvedSignals(for settings: AppSettings) -> ToolSignals {
        ToolSignals(
            webToolsAllowed: settings.outboundWebAllowed,
            showsGenerationStats: settings.showsGenerationStats
        )
    }

    /// Republishes the derived values after a settings write, assigning each one **only when it moved**.
    ///
    /// Writing a value back unchanged still fires an Observation change, and every window reading the paint
    /// is then torn down and rebuilt for a preference that changes nothing on screen. A view holding
    /// several presentations is where that costs the most: it is how a presentation stack ends up dismissed
    /// by a button pressed inside one of its own sheets.
    ///
    /// Called from `mutate` and `reload` rather than from a `didSet`, deliberately: the Observation macro
    /// rewrites stored properties, and an observer attached to one of them is behaviour this module can
    /// only compile on CI, so it should not depend on how the two interact.
    func republish(from updated: AppSettings) {
        let nextChrome = Self.resolvedChrome(for: updated)
        if nextChrome != chrome { chrome = nextChrome }
        let nextSignals = Self.resolvedSignals(for: updated)
        if nextSignals != toolSignals { toolSignals = nextSignals }
    }
}
