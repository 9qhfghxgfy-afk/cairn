import SwiftUI
import CairnChatDomain

/// The `(i)` control that carries a control's explanation.
///
/// The copy lives in the domain (`SamplingKey.explainer`, `ContextKey.explainer`, `SettingInfoKey.info`) and
/// is reached from here, so the sheet, a settings screen, a later help screen, and a test can never disagree
/// about what a knob does.
///
/// A popover rather than a line of text under every control, because ten controls with three lines of
/// explanation each is a screen where the controls are the minority. The explanation is one tap away and
/// never in the way — and it is still reachable with VoiceOver, since the button is an accessibility element
/// with the full text as its label.
struct InfoButton: View {
    private let title: String
    private let text: String

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    /// The catalog form. Preferred over the two-string form wherever a key exists, because it is the form a
    /// test has already read: a row that names a key cannot open a card nobody wrote.
    init(key: SettingInfoKey) {
        let entry = key.info
        self.init(title: entry.title, text: entry.detail)
    }

    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(CairnTheme.stoneLight)
                // The glyph alone is about fifteen points across, which is a target people miss — and a miss
                // next to a toggle or a navigation row is worse than a miss in empty space, because the miss
                // lands on something that changes state. The frame widens the hit area without moving pixels.
                .frame(minWidth: Self.hitEdge, minHeight: Self.hitEdge)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(text)")
        .popover(isPresented: $showing, arrowEdge: .top) {
            InfoPopoverContent(title: title, text: text)
        }
    }

    /// The shortest side of the tap area, in points. Exposed so a test can state the promise rather than
    /// restate the constant.
    static let hitEdge: CGFloat = 28
}

