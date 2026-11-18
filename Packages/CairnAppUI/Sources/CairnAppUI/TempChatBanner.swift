import SwiftUI
import CairnChatDomain

/// The line that says this chat will not survive, and the one action that can save something from it.
///
/// Temporary chat is a promise Cairn makes and keeps: nothing written here reaches disk, and the app
/// closing really does lose it. A promise nobody can see is not a promise, so the line stays up for as long
/// as it is true rather than only on the first message — the moment a person decides whether to keep an
/// answer is usually several turns in.
///
/// "Keep a copy" answers the worry the line raises, and does it without moving anybody: the copy is written
/// as an ordinary saved chat and this chat stays temporary. Taking the user out of the chat they are typing
/// in is not what saving should mean.
struct TempChatBanner: View {
    let workspace: ChatWorkspace
    @State private var savedTitle: String?
    @State private var failed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .foregroundStyle(CairnTheme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(savedTitle ?? "Temporary chat \u{2014} nothing here is written to disk")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CairnTheme.stoneLight)
            }
            Spacer(minLength: 0)
            Button("Keep a copy", action: keep)
                .buttonStyle(.bordered)
                .tint(CairnTheme.amber)
                .disabled(savedTitle != nil)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CairnTheme.amber.opacity(0.12))
        )
    }

    private var detail: String {
        if savedTitle != nil {
            return "The copy is in the chats list. This chat is still the temporary one."
        }
        if failed {
            return "The copy could not be written. This chat is still only in memory."
        }
        return "Closing the app loses it. A copy lands in the list and leaves you here."
    }

    private func keep() {
        guard let saved = workspace.keepCopyOfCurrentChat() else {
            failed = true
            return
        }
        savedTitle = ChatListQuery.visibleTitle(saved)
    }
}
