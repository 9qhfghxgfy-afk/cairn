import SwiftUI
import CairnChatDomain

/// The badge that says this conversation has let a tool out to the public internet.
///
/// **Persistent, not a toast.** The moment a search finishes is the last moment a user can be shown
/// something they will act on; a badge that disappears leaves them reasoning about a network trip that
/// happened two turns ago. So the badge is read off the stored nodes of this conversation and stays up
/// until the conversation ends, and its wording names what left rather than the tool that carried it —
/// which is the fact worth knowing.
public struct ToolsOutboundBadge: View {
    /// True when a tool in this conversation reached the public internet.
    let usedWebTools: Bool
    /// A short line naming what went out, shown beside the badge where there is room.
    var detail: String?

    public init(usedWebTools: Bool, detail: String? = nil) {
        self.usedWebTools = usedWebTools
        self.detail = detail
    }

    public var body: some View {
        if usedWebTools {
            HStack(spacing: 5) {
                Image(systemName: "globe.badge.chevron.backward").font(.caption2)
                Text(detail ?? "Web tools sent data out")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(CairnTheme.rust.opacity(0.2)))
            .overlay(Capsule().stroke(CairnTheme.rust.opacity(0.55), lineWidth: 1))
            .foregroundStyle(CairnTheme.rust)
            .accessibilityLabel("Outbound: a web tool sent data from this conversation to the internet")
        }
    }
}
