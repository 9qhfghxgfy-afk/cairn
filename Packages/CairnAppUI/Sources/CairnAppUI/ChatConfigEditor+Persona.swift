import SwiftUI
import CairnChatDomain

/// The persona — the user's own system prompt, and the only part of the system message that is theirs.
///
/// It goes first and verbatim, ahead of everything Cairn adds. That ordering is the contract the
/// preview shows: a persona written as instructions stays instructions, and an injection never sits on
/// top of it and re-reads it.
extension ChatConfigEditor {
    var personaSection: some View {
        Section {
            TextField(
                "You are a patient teacher. Never give the answer before the hint.",
                text: $config.persona,
                axis: .vertical
            )
            .lineLimit(3...8)
            .foregroundStyle(.primary)

            HStack(alignment: .top, spacing: 8) {
                Text(
                    "Sent first, exactly as written. Left empty, nothing of yours is sent."
                )
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
                Spacer(minLength: 4)
                InfoButton(title: "Persona", text: Self.personaExplainer)
            }
        } header: {
            SectionHeader(
                "Persona",
                count: config.persona.trimmingCharacters(in: .whitespaces).isEmpty ? nil : 1
            )
        }
    }

    /// Written here, not in the domain: this is about the sheet's contract with the user, and the
    /// persona has no wire encoding of its own to keep the wording next to.
    ///
    /// A computed property, not a stored one: `ChatConfigEditor` is generic over the section its
    /// mounting screen adds, and Swift does not allow a stored static property in a generic type.
    static var personaExplainer: String {
        """
        Your system prompt, sent as the first message of the conversation, word for word. Cairn puts \
        it ahead of its own injected facts, so instructions you write are never re-framed by a line \
        Cairn added.

        Empty means no persona. If every injected-context toggle below is also off, this conversation \
        has no system message at all — your words reach the model with nothing in front of them.
        """
    }
}
