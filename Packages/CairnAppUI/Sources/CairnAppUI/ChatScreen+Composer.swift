import SwiftUI
import CairnChatDomain

/// The composer: the text field, the paperclip, the files it is holding, and what happens on Send.
///
/// Kept apart from `ChatScreen.swift` because the composer is the only part of the screen that owns a second
/// piece of state — `ComposerDraft` — and the only part that can say no. It is also the part with the most
/// sentences attached to it: a refusal, a vision warning, and a statement about where these files actually
/// live all belong beside the button that would send them.
///
/// Send has three exits, and the order matters:
///
/// 1. nothing to send — no text and no files is not a message;
/// 2. the vision gate blocks it — the draft stays full and the warning stays up, because a photo the user
///    picked is not thrown away to satisfy a rule the composer could have stated earlier;
/// 3. it goes — text cleared, draft cleared, both rows written.
///
/// The gate consulted here is the session's own decision, produced by the same function the send produces two
/// statements later. This is not a second rule with its own opinion about engines; it is the same rule read
/// early enough to keep the user's files when it says no.
extension ChatScreen {
    /// The composer, sized so the answer above it can still be read.
    ///
    /// Three things keep the keyboard from owning the screen. It grows to four lines and no further,
    /// so a long message scrolls inside its own field instead of pushing the transcript off the top;
    /// scrolling the transcript dismisses it with the finger already moving; and there is a control
    /// that closes it, both in the keyboard's own bar and in the row itself, because a bar item a user
    /// has never seen before is not a control they will find under a keyboard they want gone.
    var composer: some View {
        VStack(spacing: 5) {
            if let session {
                ComposerChips(session: session, theme: settings)
                // What this engine will not do, said beside the switch that asked for it. The switch
                // stays live — a backend still gets the tools through the prompt protocol — but an
                // empty reasoning panel next to a switch that says "on" reads as a fault unless the
                // screen has already said what this engine emits.
                ForEach(session.engineCapabilityNotes, id: \.self) { note in
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(CairnTheme.stoneLight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ComposerAttachments(
                draft: draft,
                session: session,
                temporaryChat: workspace.temporaryChat,
                storageAvailable: session?.attachmentStorageAvailable ?? workspace.attachmentStorageAvailable
            )
            if let error = workspace.lastError ?? session?.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.rust)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 8) {
                AttachmentPickerMenu(draft: draft)
                TextField("Ask Cairn…", text: $composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    // One line at rest, four at most: a field that grows without limit is a field that
                    // eventually fills the screen with itself.
                    .lineLimit(1...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CairnTheme.slate)
                    )
                    .foregroundStyle(.white)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit(send)

                if composerFocused {
                    // Only while the keyboard is up — a dismiss control for a keyboard that is not
                    // there is a button that does nothing, and this app does not ship those.
                    Button {
                        composerFocused = false
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title3)
                            .padding(2)
                    }
                    .foregroundStyle(CairnTheme.stoneLight)
                    .accessibilityLabel("Hide the keyboard")
                }

                if session?.isBusy == true {
                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .padding(10)
                            .background(Circle().fill(CairnTheme.rust.opacity(0.85)))
                            .foregroundStyle(.white)
                    }
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .padding(10)
                            .background(Circle().fill(CairnTheme.amber))
                            .foregroundStyle(CairnTheme.slateDeep)
                    }
                    // A photo with no words is still a message — "what is in this picture?" does not need to
                    // be typed. Only an empty draft and an empty field disable the button; the vision gate is
                    // not expressed as a dead button, because a button that will not explain itself reads as
                    // a broken app, and the amber line above already says what is wrong.
                    .disabled(
                        composerText.trimmingCharacters(in: .whitespaces).isEmpty && draft.isEmpty
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    func send() {
        let text = composerText
        let staged = draft.attachments
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !staged.isEmpty else { return }
        guard let session else { return }
        if session.visionDecision(for: staged).blocksSend { return }
        session.send(text, attachments: staged)
        composerText = ""
        draft.clear()
    }

    func stop() {
        session?.cancelStreaming()
    }
}
