import SwiftUI
import CairnChatDomain

/// Taking a chat off the device, in the two forms that do different jobs.
///
/// Markdown is for reading: a person can open it in anything, and headings, lists and code blocks survive
/// as the text they were written in. A Cairn file is for coming back: it carries the whole tree — every
/// branch, every candidate draft — and opens back into the app here or on another device.
///
/// A temporary chat is spoken about rather than exported. Exporting it from the saved store would hand
/// back the one thing the user asked the app to forget, so the screen says what to do instead.
struct ChatExportSheet: View {
    let workspace: ChatWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var file: ExportedChatFile?
    @State private var problem: String?

    var body: some View {
        List {
            Section("This chat") {
                if currentChat == nil {
                    Text(temporaryExplanation)
                        .font(.callout)
                        .foregroundStyle(CairnTheme.stoneLight)
                } else {
                    buttons(conversationID: currentChat?.id)
                }
            }
            Section("Every saved chat") {
                buttons(conversationID: nil)
            }
            Section {
                Text(privacyNote)
                    .font(.footnote)
                    .foregroundStyle(CairnTheme.stoneLight)
                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(CairnTheme.rust)
                }
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
        }
        .sheet(item: $file) { shared in ChatShareSheet(url: shared.url) }
    }

    private var currentChat: Conversation? {
        guard !workspace.temporaryChat, let id = workspace.session?.conversation.id else { return nil }
        return workspace.chats().first { $0.id == id }
    }

    private var temporaryExplanation: String {
        "This chat is temporary, so it is not in the saved store an export reads from. Keep a copy of it "
            + "from the chats list first, then export that."
    }

    private var privacyNote: String {
        "Nothing leaves this device until you choose somewhere to put the file. The share sheet is the only "
            + "thing that moves it, and it is opened by your tap."
    }

    private func buttons(conversationID: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                export(conversationID: conversationID, markdown: true)
            } label: {
                Label("Markdown file (.md)", systemImage: "doc.plaintext")
            }
            Button {
                export(conversationID: conversationID, markdown: false)
            } label: {
                Label("Cairn file (.cairn)", systemImage: "arrow.2.squarepath")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func export(conversationID: UUID?, markdown: Bool) {
        let text = workspace.transcriptMarkdown(conversationID: conversationID)
        let data = markdown ? text.map { Data($0.utf8) } : workspace.exportFileData(conversationID: conversationID)
        guard let data else {
            problem = workspace.lastError ?? "There is nothing to export yet."
            workspace.lastError = nil
            return
        }
        let chat = conversationID.flatMap { id in workspace.chats().first { $0.id == id } }
        let name = ChatFileNames.name(for: chat, markdown: markdown)
        guard let written = ExportedChatFile.write(name: name, data: data) else {
            problem = "Cairn could not write the file it was asked to share."
            return
        }
        file = written
    }
}
