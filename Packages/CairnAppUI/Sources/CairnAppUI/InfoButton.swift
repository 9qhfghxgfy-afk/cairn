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
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.callout)
            }
            .padding(12)
            .frame(maxWidth: 300, alignment: .leading)
            .presentationDetents([.medium, .large])
        }
    }
}
