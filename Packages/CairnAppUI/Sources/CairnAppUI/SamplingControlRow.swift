import SwiftUI
import CairnChatDomain

/// One sampling knob, and the state that matters most on this screen: whether the chat asserts it at
/// all. A control that is off sends nothing and leaves the server's own answer in force, so the row
/// says which of the two it is — and says it again when the engine in use cannot read the key, because
/// a knob the server ignores silently is a knob the user believes is working.
///
/// The set/unset state is the row's, not each editor's: a slider, a ladder and a seed field all need
/// the same wording around the same decision.
///
/// Unset is drawn, not hidden. The control collapses to `Not set` with Cairn's reference value named in
/// the status line, so the user can see what the reference is *and* that it is not being sent — the two
/// facts that make "let the server decide" an informed choice rather than a blank.
struct SamplingControlRow<Editor: View>: View {
    let title: String
    let explainer: String
    let isSet: Bool
    let isSupported: Bool
    /// The value in force when `isSet` — amber, because the chat is asserting it.
    let valueText: String
    /// Cairn's reference point, named when unset. Never sent; see `SamplingReference`.
    let reference: String
    let onSetChanged: (Bool) -> Void
    @ViewBuilder var editor: () -> Editor

    init(
        title: String,
        explainer: String,
        isSet: Bool,
        isSupported: Bool,
        valueText: String,
        reference: String,
        onSetChanged: @escaping (Bool) -> Void,
        @ViewBuilder editor: @escaping () -> Editor
    ) {
        self.title = title
        self.explainer = explainer
        self.isSet = isSet
        self.isSupported = isSupported
        self.valueText = valueText
        self.reference = reference
        self.onSetChanged = onSetChanged
        self.editor = editor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSet ? .primary : CairnTheme.stoneLight)
                        InfoButton(title: title, text: explainer)
                    }
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer(minLength: 6)
                Toggle(isOn: setBinding) {
                    Text(isSet ? "Set" : "Not set")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.switch)
                .tint(CairnTheme.amber)
            }

            if isSet {
                HStack(spacing: 8) {
                    editor()
                    Text(valueText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CairnTheme.amber)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }

            if !isSupported {
                Label(
                    isSet
                        ? "This server does not read that key, so Cairn leaves it out of the request."
                        : "This server does not read that key.",
                    systemImage: "slash.circle"
                )
                .font(.caption)
                .foregroundStyle(isSet ? CairnTheme.rust : CairnTheme.stoneLight)
            }
        }
        .padding(.vertical, 2)
    }

    /// What this knob does to the request right now: the value the chat asserts, or the reference value
    /// Cairn is deliberately not sending.
    private var statusLine: String {
        if isSet { return "This chat asserts \(valueText)." }
        return "Server default — Cairn sends nothing. Reference: \(reference)."
    }

    private var setBinding: Binding<Bool> {
        Binding(get: { isSet }, set: { onSetChanged($0) })
    }
}

/// How Cairn's reference points are spoken out loud. These are reference points, not values Cairn
/// sends — the whole reason a row can render at a position and still assert nothing.
func referenceText(_ value: Double) -> String {
    String(format: "%.2f", value)
}

func referenceText(_ value: Int) -> String {
    SamplingReference.contextLabel(value)
}
