import SwiftUI
import CairnChatDomain

/// The whole configuration form: persona, answer style, the knobs, the injected context, and a live
/// preview of the block Cairn will send.
///
/// One form serves two screens — the per-chat sheet and the Default Configuration editor in Settings.
/// They must be the same controls with the same wording, because a user who learned the per-chat sheet
/// should not have to relearn the settings screen, and two wordings drift.
///
/// The sections live in their own files: persona, sampling, and context each have enough going on to
/// deserve one, and a 400-line form is the kind of file nobody edits correctly.
struct ChatConfigEditor<Extra: View>: View {
    @Binding var config: ChatConfig
    /// Which knobs the engine in use will read. `Settings` passes `.all`, since a baseline has to be
    /// writable for servers other than the one selected right now; the request filter then drops a key
    /// per server, and the sheet says so out loud.
    var support: SamplingSupport = .all
    /// The exact system block, produced by the same call the stream uses. `nil` hides the section.
    var preview: String?
    var supportNote: String?
    /// Owns the randomness for the seed control, so a preview or a test can make it repeatable.
    var seedCandidate: () -> Int = { Int.random(in: 1...999_999) }
    /// One section the mounting screen supplies, placed between the injections and the live preview.
    /// The per-chat sheet uses it for the hybrid rows; the Default Configuration editor passes nothing,
    /// because a baseline has no engines in front of it to choose between.
    @ViewBuilder var extra: () -> Extra

    init(
        config: Binding<ChatConfig>,
        support: SamplingSupport = .all,
        preview: String? = nil,
        supportNote: String? = nil,
        seedCandidate: @escaping () -> Int = { Int.random(in: 1...999_999) },
        @ViewBuilder extra: @escaping () -> Extra
    ) {
        self._config = config
        self.support = support
        self.preview = preview
        self.supportNote = supportNote
        self.seedCandidate = seedCandidate
        self.extra = extra
    }

    var body: some View {
        Form {
            personaSection
            samplingSection
            contextSection
            extra()
            if let preview { previewSection(preview) }
        }
        .scrollContentBackground(.hidden)
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
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask for reasoning").font(.subheadline)
                    Text(
                        "The panel appears only if this model actually returns reasoning."
                    )
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                }
                Spacer(minLength: 4)
                InfoButton(
                    title: "Ask for reasoning",
                    text: "Cairn asks this backend for its reasoning and shows it only if the backend "
                        + "actually returns any. Cairn never writes a thinking display around an answer "
                        + "it has no reasoning for, and never invents one."
                )
            }
        }
        .tint(CairnTheme.amber)
    }
}

extension ChatConfigEditor where Extra == EmptyView {
    /// The form on its own — the shape the Default Configuration editor uses, where there is no pair
    /// of engines to choose between because a baseline is written before any server is picked.
    init(
        config: Binding<ChatConfig>,
        support: SamplingSupport = .all,
        preview: String? = nil,
        supportNote: String? = nil,
        seedCandidate: @escaping () -> Int = { Int.random(in: 1...999_999) }
    ) {
        self.init(
            config: config, support: support, preview: preview, supportNote: supportNote,
            seedCandidate: seedCandidate
        ) {
            EmptyView()
        }
    }
}
