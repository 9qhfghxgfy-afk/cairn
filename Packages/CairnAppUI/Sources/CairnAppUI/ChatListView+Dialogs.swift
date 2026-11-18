import SwiftUI
import CairnChatDomain

/// The list's toolbar and its two questions: what should this chat be called, and is it really meant to
/// go away.
///
/// Both acts get asked about. A rename is cheap but it is the only name a chat will ever have, and a
/// delete takes the whole tree with it — every branch, not only the one on screen — so neither happens on
/// a single tap.
extension ChatListView {

    var buttons: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button("New chat", systemImage: "square.and.pencil") {
                    workspace.startNewChat()
                    dismiss()
                }
                Button("Export\u{2026}", systemImage: "square.and.arrow.up") {
                    showingExport = true
                }
                Button("Import a chat file\u{2026}", systemImage: "square.and.arrow.down") {
                    showingImport = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Chat actions")

            Button("Done") { dismiss() }
        }
    }

    /// The alert is driven by which chat is picked rather than by a separate flag, so the two cannot
    /// disagree about what is being renamed.
    var isRenaming: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    var renameButtons: some View {
        Group {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let chat = renameTarget { workspace.rename(conversationID: chat.id, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    var deletePrompt: String {
        guard let chat = deleteTarget else { return "Delete this chat?" }
        return "Delete \u{201c}\(ChatListQuery.visibleTitle(chat))\u{201d}?"
    }

    var isDeleting: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    var deleteButtons: some View {
        Group {
            Button("Delete the whole chat", role: .destructive) {
                if let chat = deleteTarget { workspace.delete(conversationID: chat.id) }
                deleteTarget = nil
            }
            Button("Keep it", role: .cancel) { deleteTarget = nil }
        }
    }
}
