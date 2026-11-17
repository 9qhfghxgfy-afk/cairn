import SwiftUI
import CairnChatDomain

/// One sampling knob, and the state that matters most on this screen: whether the chat asserts it at
/// all. A control that is off sends nothing and leaves the server's own answer in force, so the row
/// says which of the two it is — and says it again when the engine in use cannot read the key, because
/// a knob the server ignores silently is a knob the user believes is working.
///
/// The set/unset state is the row's, not each editor's: a slider, a ladder and a seed field all need
/// the same wording around the same decision.
struct SamplingControlRow<Editor: View>: View {
    let title: String
    let explainer: String
    let isSet: Bool
    let isSupported: Bool
    let valueText: String
    let onSetChanged: (Bool) -> Void
    @ViewBuilder var editor: () -> Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSet ? .primary : CairnTheme.stoneLight)
                    Text(explainer)
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

    private var setBinding: Binding<Bool> {
        Binding(get: { isSet }, set: { onSetChanged($0) })
    }
}

/// The reference value shown while a knob is unset. These are Cairn's published reference points, not
/// values Cairn sends — the whole reason the row can render at a position and still assert nothing.
func referenceText(_ value: Double) -> String {
    String(format: "%.2f", value)
}

func referenceText(_ value: Int) -> String {
    SamplingReference.contextLabel(value)
}
