import SwiftUI
import CairnChatDomain

/// A presented screen: its own navigation stack, painted with the theme it was presented from.
///
/// Every sheet in Cairn used to open a bare `NavigationStack`, and a bare stack wears the system's own
/// chrome — a stock grouped background, the system blue on its buttons, its own bar material — no matter
/// which theme the app is set to. That is the shape of the "the theme does not propagate" complaint: the
/// transcript changed and Settings, Servers, the chat list and every editor behind them did not, because
/// nothing ever told those windows which theme to wear.
///
/// One container, so a presentation cannot forget. Painted twice on purpose: **inside** the stack, where a
/// nav bar actually reads its bar styling from, and **outside** it, so a screen pushed from here — or a
/// sheet presented from here — inherits the same paint instead of meeting the environment default.
public struct CairnSheet<Content: View>: View {
    private let theme: ThemeModel?
    private let content: () -> Content

    /// `theme` is handed in rather than read here because a sheet is a fresh window's content: the object
    /// that owns the user's choice has to cross that gap explicitly. With no theme, whatever the
    /// environment already carries is kept — correct for a stack pushed inside a themed presentation.
    public init(theme: ThemeModel? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.theme = theme
        self.content = content
    }

    public var body: some View {
        NavigationStack {
            content().cairnPresentation(theme: theme)
        }
        // And outside it, so a screen pushed from here — or a sheet presented from here — inherits the
        // same paint instead of meeting the environment default. The modifier carries the sheet's own
        // background too, which is what stops a presented window sitting on the system's card colour.
        .cairnPresentation(theme: theme)
    }
}
