import SwiftUI
import CairnChatDomain

/// One optional token: a secure field, and what to do with what was typed into it.
///
/// `SecureField`, so the value is dotted while it is being typed. That is not decoration: a token row in
/// Settings is the one place in this app where a secret is entered by hand, and a shoulder, a screen share,
/// or a screenshot all look at Settings. The field is also the only place the value exists in this module —
/// the row asks the model whether a token is saved, never what it is.
///
/// The keyboard discipline is the same one every other editing row in this app uses, and for the same
/// reason: the system keyboard covers the Save button, and a person who taps past the field gets nothing
/// back. Dismiss at the top of both actions so a press never has to fight the keyboard for the tap.
struct ModelTokenRow: View {
    /// Plain, not `@ObservedObject`: the model is `@Observable`, so the properties this body reads are
    /// tracked on their own. That also keeps Settings — which holds this model as an optional value — inside
    /// the same tracking, without a property wrapper on every parent that passes it down.
    var model: ModelTokenModel
    let kind: ModelTokenKind

    @FocusState private var focusedField: Bool

    var body: some View {
        InfoRow(
            key: kind.infoKey,
            caption: model.isSaved(for: kind)
                ? "Saved on this phone. Clear the field and press Save to take it off."
                : kind.caption,
            control: { control }
        )
    }

    private var control: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(kind == .huggingFace ? "hf_…" : "token", text: draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($focusedField)
                .accessibilityIdentifier("cairn.settings.token." + kind.rawValue)

            HStack(spacing: 10) {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(CairnTheme.amber)
                    .disabled(draft.wrappedValue
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("cairn.settings.token." + kind.rawValue + ".save")

                if model.isSaved(for: kind) {
                    Button("Remove", role: .destructive) { removeToken() }
                        .buttonStyle(.bordered)
                        .tint(CairnTheme.rust)
                        .accessibilityIdentifier("cairn.settings.token." + kind.rawValue + ".remove")
                }

                Text(model.isSaved(for: kind) ? "Saved" : "Not saved")
                    .font(.caption)
                    .foregroundStyle(model.isSaved(for: kind) ? CairnTheme.moss : CairnTheme.stoneLight)
            }
        }
    }

    /// The field reads and writes the model's draft rather than local `@State`, so a list refresh that
    /// rebuilds this row mid-word does not silently delete half a typed token. The draft is cleared on save
    /// and on remove, so nothing typed here outlives the row.
    private var draft: Binding<String> {
        Binding(
            get: { model.draft(for: kind) },
            set: { model.setDraft($0, for: kind) }
        )
    }

    /// Both actions close the keyboard, because the field that was just used is sitting on top of the notice
    /// that says whether the action worked — and this app ships no button whose only visible effect is that
    /// something else stayed on screen.
    private func save() {
        focusedField = false
        model.save(model.draft(for: kind), for: kind)
    }

    private func removeToken() {
        focusedField = false
        model.remove(for: kind)
    }
}
