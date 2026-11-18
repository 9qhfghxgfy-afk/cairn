import SwiftUI
import CairnChatDomain
import UniformTypeIdentifiers

/// Every chat kept on this device, and the ways one leaves or arrives.
///
/// The rows come from the workspace's snapshot in the order the domain sets: most recently touched first,
/// filtered on the title. Nothing here paginates a chat away or caps the list — a chat you made is a row
/// you are owed.
///
/// Every action goes through the workspace rather than the array on screen, because the array is a
/// snapshot: acting on it could rename or delete a chat the store has already moved on from.
struct ChatListView: View {
    // Internal, not `private`: the rows, buttons and file handling live in
    // ChatListView+Actions.swift, which is a second file of the same type.
    @State var query = ""
    @State var renameTarget: Conversation?
    @State var renameText = ""
    @State var deleteTarget: Conversation?
    @State var showingImport = false
    @State var showingExport = false
    @State var notice: String?
    let workspace: ChatWorkspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(CairnTheme.moss)
            }
            if workspace.temporaryChat { temporaryRow }
            ForEach(chats) { chat in
                row(chat)
            }
            if chats.isEmpty {
                Text(query.isEmpty ? "No chats here yet." : "No chat has that title.")
                    .font(.callout)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
        }
        .scrollContentBackground(.hidden)
        .background(CairnTheme.slateDeep)
        .searchable(text: $query, prompt: "Search titles")
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { buttons }
        .alert("Rename chat", isPresented: isRenaming) { renameButtons }
        .confirmationDialog(deletePrompt, isPresented: isDeleting, titleVisibility: .visible) { deleteButtons }
        .fileImporter(
            isPresented: $showingImport,
            allowedContentTypes: [.json, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            importFile(result)
        }
        .sheet(isPresented: $showingExport) {
            NavigationStack { ChatExportSheet(workspace: workspace) }
        }
    }

    private var chats: [Conversation] { workspace.chats(matching: query) }
}
