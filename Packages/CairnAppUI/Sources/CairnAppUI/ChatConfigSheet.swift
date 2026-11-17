import SwiftUI
import CairnChatDomain

/// The per-chat configuration sheet: persona, knobs, injections, and the exact system message the
/// chat will send.
///
/// Edits go to a draft and are written once, on Done. Live writes would mean a scroll past a slider
/// silently changing a conversation, and a configuration that changes answers deserves the one tap that
/// says "yes, this one". Cancel therefore discards, which is also the only way back out of a mistake.
public struct ChatConfigSheet: View {
    private let session: ChatSessionModel
    private let defaults: ChatConfig
    /// "Use these settings for new chats." Optional because the sheet is usable without a settings
    /// store wired (previews, tests); the chat itself always saves.
    private var makeDefault: ((ChatConfig) -> Void)?
    @State private var draft: ChatConfig
    @Environment(\.dismiss) private var dismiss

    public init(
        session: ChatSessionModel,
        defaults: ChatConfig,
        makeDefault: ((ChatConfig) -> Void)? = nil
    ) {
        self.session = session
        self.defaults = defaults
        self.makeDefault = makeDefault
        _draft = State(initialValue: session.conversation.config)
    }

    public var body: some View {
        NavigationStack {
            ChatConfigEditor(
                config: $draft,
                support: session.samplingSupport,
                preview: draftPreview,
                supportNote: engineNote
            )
            .navigationTitle("This chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        session.updateConfig(draft)
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    /// Produced from the draft against the live turn, so moving a toggle moves the text below it — and
    /// what moves is the text that will be sent.
    private var draftPreview: String {
        draft.systemPrompt(in: session.contextEnvironment, turn: session.currentTurnContext)
    }

    private var engineNote: String? {
        if session.samplingSupport == .none {
            return session.activeProvider == nil
                ? "No engine is selected, so Cairn claims no knobs. Pick a server and this section "
                    + "will offer what that server actually reads."
                : "This engine reads no sampling keys, so nothing set here reaches it. Cairn sends "
                    + "the conversation and nothing else."
        }
        let dropped = draft.unsupportedKeys(for: session.samplingSupport)
        guard !dropped.isEmpty else { return nil }
        let names = dropped.map(\.displayName).joined(separator: ", ")
        return "This server does not read: \(names). Cairn leaves those keys out of its requests "
            + "rather than sending a key the server would reject."
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                draft.sampling = .unset
            } label: {
                Label("Clear every knob", systemImage: "arrow.counterclockwise")
            }
            .disabled(draft.configuredOptionCount == 0)

            Button {
                draft.reset(to: defaults)
            } label: {
                Label("Reset to defaults", systemImage: "leaf")
            }

            Spacer(minLength: 0)

            if makeDefault != nil {
                Button {
                    session.updateConfig(draft)
                    makeDefault?(draft)
                    dismiss()
                } label: {
                    Text("Use for new chats")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(CairnTheme.amber)
            }
        }
        .font(.caption)
        .padding(12)
        .background(Color(.secondarySystemBackground))
    }
}
