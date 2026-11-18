import SwiftUI
import CairnChatDomain

/// The list's rows, buttons and file handling — the parts of the screen that change a chat or move one
/// across the edge of the device.
extension ChatListView {

    func row(_ chat: Conversation) -> some View {
        ChatRowView(
            chat: chat,
            isOpenChat: chat.id == workspace.session?.conversation.id,
            openChat: { open(chat) }
        )
        .listRowBackground(CairnTheme.slate.opacity(0.5))
        // One swipe, one edge. Two `.swipeActions` calls on one row is the shape SwiftUI is least
        // predictable about, and three buttons on the trailing edge is a thing people already know how to
        // do: pull left, pick one.
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { deleteTarget = chat }
            Button("Duplicate") { workspace.duplicate(conversationID: chat.id) }
                .tint(CairnTheme.moss)
            Button("Rename") {
                renameText = ChatListQuery.visibleTitle(chat)
                renameTarget = chat
            }
            .tint(CairnTheme.amber)
        }
    }

    /// The chat currently open, said in the same breath as the list: it is not in here, and the reason
    /// why is on the row. "Keep a copy" writes it to disk and leaves the temporary one open, which is the
    /// only honest way to save a chat the app is meant to forget.
    var temporaryRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("This chat is temporary")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text("It is not in this list and will not survive the app closing.")
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            Spacer(minLength: 0)
            Button("Keep a copy") {
                guard let saved = workspace.keepCopyOfCurrentChat() else { return }
                notice = "Saved a copy as \u{201c}\(ChatListQuery.visibleTitle(saved))\u{201d}. This chat is still the temporary one."
            }
            .buttonStyle(.borderedProminent)
            .tint(CairnTheme.amber)
        }
        .padding(.vertical, 4)
    }

    /// Opening a saved chat out of a temporary one leaves temporary mode. That is not a side effect to
    /// apologise for: the toggle never carries history over, and the temporary chat has already been said
    /// out loud to be going away. Staying in it while a tap quietly does nothing would be the worse answer.
    func open(_ chat: Conversation) {
        if workspace.temporaryChat { workspace.temporaryChat = false }
        workspace.select(conversationID: chat.id)
        dismiss()
    }

    /// Reading a file the user picked. Nothing is guessed about it: the bytes are handed to the importer,
    /// which either recognises them or refuses them, and the refusal is what gets said.
    func importFile(_ result: Result<[URL], Error>) {
        // Two steps rather than one condition. `guard case .success(let urls), let url = urls.first` does not
        // parse — a binding after a pattern-matching condition is rejected — and a version that tries to be
        // cleverer than the compiler is not worth the line it saves.
        var picked: [URL] = []
        if case .success(let urls) = result { picked = urls }
        guard let url = picked.first else {
            if case .failure(let failure) = result { notice = failure.localizedDescription }
            return
        }
        // A file outside the app belongs to the system. The claim is taken for the read and dropped after,
        // not held: Cairn keeps nothing from a file the user did not ask it to keep.
        let claimed = url.startAccessingSecurityScopedResource()
        defer { if claimed { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let plan = workspace.importChatFile(try Data(contentsOf: url)) else {
                notice = workspace.lastError ?? "That file could not be imported."
                workspace.lastError = nil
                return
            }
            notice = importSpoken(plan)
        } catch {
            notice = "That file could not be read."
        }
    }

    func importSpoken(_ plan: ChatImportPlan) -> String {
        let chats = plan.conversations.count
        let messages = plan.nodes.count
        let single = chats == 1 ? "chat" : "chats"
        if plan.assignedFreshIDs {
            return "Imported \(chats) \(single) as a copy — \(messages) messages. Nothing already here was changed."
        }
        return "Imported \(chats) \(single) — \(messages) messages."
    }
}
