import SwiftUI
import CairnChatDomain

/// The whole configuration form: persona, answer style, the knobs, the injected context, and a live
/// preview of the block Cairn will send.
///
/// One form serves two screens — the per-chat sheet and the Default Configuration editor in Settings.
/// They must be the same controls with the same wording, because a user who learned the per-chat sheet
/// should not have to relearn the settings screen, and two wordings drift.
struct ChatConfigEditor: View {
    @Binding var config: ChatConfig
    /// Which knobs the engine in use will read. `Settings` passes `.all`, since a baseline has to be
    /// writable for servers other than the one selected right now; the request filter then drops a key
    /// per server, and the sheet says so out loud.
    var support: SamplingSupport = .all
    /// The exact system block, produced by the same call the stream uses. `nil` hides the section.
    var preview: String?
    var supportNote: String?

    var body: some View {
        Form {
            personaSection
            samplingSection
            contextSection
            if let preview { previewSection(preview) }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Persona

    var personaSection: some View {
        Section {
            TextField(
                "You are a patient teacher. Never give the answer before the hint.",
                text: $config.persona,
                axis: .vertical
            )
            .lineLimit(3...8)
            .foregroundStyle(.primary)

            Text(
                "Sent first, exactly as written, ahead of anything Cairn adds. Left empty, nothing of "
                    + "yours is sent — and if every toggle below is off, there is no system message at all."
            )
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        } header: {
            SectionHeader("Persona", count: config.persona.trimmingCharacters(in: .whitespaces).isEmpty ? nil : 1)
        }
    }

    // MARK: - Answer style and thinking

    var answerStyleRow: some View {
        Picker("Answer style", selection: $config.responseFormat) {
            ForEach(ResponseFormatPreference.allCases) { format in
                Text(format.displayName).tag(format)
            }
        }
        .tint(CairnTheme.amber)
    }

    var thinkingRow: some View {
        Toggle(isOn: $config.thinkingEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask for reasoning").font(.subheadline)
                Text(
                    "The panel appears only if this model actually returns reasoning. Cairn never "
                        + "writes a thinking display around an answer it has no reasoning for."
                )
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
            }
        }
        .tint(CairnTheme.amber)
    }
}

/// A section header with the "N configured" count beside it, so a screen full of controls does not
/// have to be read end to end to know whether this chat asks anything of the server.
struct SectionHeader: View {
    private let title: String
    private let count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count {
                Text("\(count) set")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CairnTheme.amber.opacity(0.2)))
                    .foregroundStyle(CairnTheme.amber)
            }
        }
    }
}
