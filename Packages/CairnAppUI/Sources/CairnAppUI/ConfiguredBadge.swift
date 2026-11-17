import SwiftUI

/// The "N configured" pill. One view so the per-chat sheet, the section headers inside it, and the
/// Default Configuration row in Settings all say the same thing in the same shape.
///
/// The count is the state that matters on these screens: a form full of controls does not have to be
/// read end to end to know whether this chat asks anything of the server.
struct ConfiguredBadge: View {
    private let count: Int

    init(_ count: Int) {
        self.count = count
    }

    var body: some View {
        Text("\(count) configured")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(CairnTheme.amber.opacity(0.2)))
            .foregroundStyle(CairnTheme.amber)
            .accessibilityLabel("\(count) options configured")
    }
}

/// A section header with the count beside it, when there is something to count.
struct SectionHeader: View {
    private let title: String
    private let count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count {
                ConfiguredBadge(count)
            }
        }
    }
}
