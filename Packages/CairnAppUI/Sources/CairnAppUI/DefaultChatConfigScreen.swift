import SwiftUI
import CairnChatDomain

/// The Default Configuration editor — the same form as the per-chat sheet, writing the baseline new
/// chats are seeded from instead of one chat's own settings.
///
/// The support table here is `.all`, unlike the chat sheet's. A baseline is written before it is known
/// which server a future chat will use, so nothing may hide a knob just because the server selected
/// right now cannot read it. The per-request filter is what keeps that honest: a server that does not
/// take `min_p` simply never receives it.
struct DefaultChatConfigScreen: View {
    private let theme: ThemeModel
    private var workspace: ChatWorkspace?
    @State private var draft: ChatConfig
    @Environment(\.dismiss) private var dismiss

    init(theme: ThemeModel, workspace: ChatWorkspace? = nil) {
        self.theme = theme
        self.workspace = workspace
        _draft = State(initialValue: theme.settings.defaultChatConfig)
    }

    var body: some View {
        ChatConfigEditor(
            config: $draft,
            support: .all,
            preview: preview,
            supportNote:
                "These settings seed every chat you start from now on. A server that cannot read a key "
                    + "is not sent that key at all, so a knob set here is a preference carried to every "
                    + "server that reads it."
        )
        .navigationTitle("New-chat defaults")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .cairnChrome(theme: theme)
    }

    /// No turn exists for a baseline, so the preview states nothing about an engine: it shows the
    /// persona and the always-on facts, which is the part a default can actually decide.
    private var preview: String {
        draft.systemPrompt(in: .current(), turn: .default)
    }

    private func save() {
        theme.saveDefaultConfig(draft)
        // The live workspace takes the new baseline now, so a chat started a second later is seeded
        // from what was just saved rather than from what the app read at launch.
        workspace?.apply(defaults: draft)
        dismiss()
    }
}
