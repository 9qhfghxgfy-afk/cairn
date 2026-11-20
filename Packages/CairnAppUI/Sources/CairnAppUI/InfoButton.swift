import SwiftUI

/// The `(i)` control that carries a control's explanation.
///
/// The copy lives in the domain (`SamplingKey.explainer`, `ContextKey.explainer`) and is reached from
/// here, so the sheet, a later help screen, and a test can never disagree about what a knob does.
///
/// A popover rather than a line of text under every control, because ten controls with three lines of
/// explanation each is a screen where the controls are the minority. The explanation is one tap away
/// and never in the way — and it is still reachable with VoiceOver, since the button is an
/// accessibility element with the full text as its label.
struct InfoButton: View {
    private let title: String
    private let text: String

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(CairnTheme.stoneLight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(text)")
        .popover(isPresented: $showing, arrowEdge: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(text).font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            // A floor as well as a ceiling: a scroll view inside a popover has no intrinsic height of
            // its own, and without a floor a short note can arrive as a sliver.
            .frame(maxWidth: 320)
            .frame(minHeight: 90, maxHeight: 380)
            .presentationDetents([.medium, .large])
            // An explanation of a control has to stay attached to that control. On iPhone a `popover`
            // is adapted to a full-screen sheet unless it is told otherwise, and a sheet that covers
            // the screen reads as a new screen rather than as the note it is — with the keyboard
            // dismissed and the composer gone with it. Apple's own usage puts this modifier on the
            // presented content rather than on the control that presents it, which is why it sits
            // inside the closure and not on the button.
            .presentationCompactAdaptation(.popover)
        }
    }
}
