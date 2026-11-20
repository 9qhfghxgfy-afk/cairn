import SwiftUI

/// The card inside an `(i)` popover: a heading, an explanation, and a floor under the height.
///
/// Its own type rather than the innards of `InfoButton`, for two reasons. The first is size — a button that
/// also lays out a card is a file about two jobs. The second is the promise: this is the view whose frame
/// decides whether iOS draws a floating card or a sliver, and a test can host it and measure it, which it
/// cannot do with a view that only exists inside a presentation.
struct InfoPopoverContent: View {
    let title: String
    let text: String

    var body: some View {
        // `ViewThatFits` rather than a bare `ScrollView`, because a scroll view has no intrinsic height and a
        // popover sizes to the content it is given: a scroll view alone arrives as a full-height card with two
        // lines in it. The unscrolled card is tried first so short copy hugs its text; the scroll view is the
        // fallback for a long card at a large Dynamic Type size.
        ViewThatFits(in: .vertical) {
            card
            ScrollView { card }
        }
        .frame(maxWidth: 320)
        // A floor as well as a ceiling: without one a short note can arrive as a sliver of card.
        .frame(minHeight: Self.minimumHeight, maxHeight: Self.maximumHeight)
        // An explanation of a control has to stay attached to that control. On iPhone a `popover` is adapted
        // to a full-screen sheet unless it is told otherwise, and a sheet that covers the screen reads as a
        // new screen rather than as the note it is — with the keyboard dismissed and the composer gone with
        // it. Apple's own usage puts this modifier on the presented content rather than on the control that
        // presents it, which is why it sits inside the closure and not on the button.
        .presentationCompactAdaptation(.popover)
    }

    /// The heading and the paragraph, as one laid-out block the two branches above share.
    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    /// The height floor, exposed so the test can state the promise instead of restating the constant.
    static let minimumHeight: CGFloat = 90
    /// The height ceiling, so a card that explains one knob never becomes a screen of its own.
    static let maximumHeight: CGFloat = 380
}
