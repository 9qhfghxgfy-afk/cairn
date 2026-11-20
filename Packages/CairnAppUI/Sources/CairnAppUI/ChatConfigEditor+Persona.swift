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
                InfoButton(key: .persona)
            }
        } header: {
            SectionHeader(
                "Persona",
                count: config.persona.trimmingCharacters(in: .whitespaces).isEmpty ? nil : 1
            )
        }
    }
}
