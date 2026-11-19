import CairnChatDomain
import SwiftUI

/// The Servers-screen entry point to the share surface, and the reason it is a row rather than a screen
/// of its own: sharing is what this phone does with the engines listed around it, so it belongs beside
/// them, and its status line is readable without opening anything.
struct ShareEntryRow: View {
    private var model: ShareModel

    init(model: ShareModel) { self.model = model }

    var body: some View {
        Section {
            NavigationLink {
                ShareView(model: model)
            } label: {
                HStack(alignment: .center) {
                    Label("Share this phone's models", systemImage: "arrow.left.arrow.right")
                    Spacer()
                    if let badge = model.badgeText {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(CairnTheme.stone.opacity(0.25), in: Capsule())
                            .foregroundStyle(CairnTheme.moss)
                    }
                }
            }
            .task { model.refresh() }
        } header: {
            Text("Sharing")
        } footer: {
            // Words, not a coloured dot: the state has to be readable without colour vision, and the
            // client count is the part that tells you someone is actually connected.
            Text(model.statusLine)
        }
    }
}
