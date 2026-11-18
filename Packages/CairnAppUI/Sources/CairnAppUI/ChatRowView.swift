import SwiftUI
import CairnChatDomain

/// One chat in the list.
///
/// The title shown is the one the list uses even when the chat has none, so a row never reads as broken
/// because nobody typed a name. The date is when the chat was last touched rather than when it was made:
/// a list of chats is a list of things you were doing, and the older date answers a question nobody in
/// front of this screen is asking.
///
/// Opening is handed in rather than reached for, so the row cannot act on a stale snapshot of the list —
/// the workspace decides what opening a chat means, and it reads the store.
struct ChatRowView: View {
    let chat: Conversation
    let isOpenChat: Bool
    let openChat: () -> Void
    @Environment(\.cairnTokens) private var tokens

    var body: some View {
        Button(action: openChat) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ChatListQuery.visibleTitle(chat))
                        .font(.body.weight(isOpenChat ? .semibold : .regular))
                        .foregroundStyle(tokens.onCanvas)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(chat.updatedAt, format: .relative(presentation: .named))
                        Text(chat.mode.displayName)
                    }
                    .font(.caption)
                    .foregroundStyle(tokens.onCanvasMuted)
                }
                Spacer(minLength: 0)
                if isOpenChat {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(tokens.accent)
                        .accessibilityLabel("Open in this chat")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
