import SwiftUI
import CairnChatDomain

/// The status dot on a server row.
///
/// It claims only what `ServerConnectionStatus` can honestly claim, and it is never the only
/// signal: the label next to it says the same thing in words, because a coloured circle alone is
/// not information a VoiceOver user or a colour-blind user can read.
struct ServerStatusDot: View {
    var status: ServerConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .overlay {
                    if status == .checking {
                        // A ring rather than a spinner: the dot has to stay one size so the row
                        // does not jump while a test runs.
                        Circle()
                            .stroke(CairnTheme.stoneLight.opacity(0.7), lineWidth: 1.5)
                    }
                }
            Text(status.shortLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
    }

    /// Green means "this server answered in this run". Grey means it cannot be reached at all —
    /// switched off, or a public server with no opt-in — which is deliberately not the same colour
    /// as a failure, because "you have not turned it on" and "it is broken" are different fixes.
    private var color: Color {
        switch status {
        case .online: return CairnTheme.moss
        case .checking: return CairnTheme.stoneLight
        case .failed: return CairnTheme.rust
        case .inert: return CairnTheme.stone
        case .unchecked: return CairnTheme.stoneLight.opacity(0.45)
        }
    }
}
