import SwiftUI
import CairnChatDomain

/// Which facts Cairn adds around the persona, in the order they are injected.
///
/// Two groups, because they behave differently. An always-injected block goes out every turn while it
/// is switched on. A conditional block goes out only when the feature it describes is actually live on
/// that turn — so the row says so, because a switch reading "on" for a block the turn never sends is a
/// wrong statement about what left the device.
extension ChatConfigEditor {
    var contextSection: some View {
        Section {
            ForEach(ContextToggleSet.alwaysOnKeys) { key in
                toggleRow(key)
            }
            ForEach(ContextToggleSet.conditionalKeys) { key in
                toggleRow(key)
            }
            Text(
                "The four at the bottom describe features. Cairn adds them only on a turn that really "
                    + "has the feature, so a turn with no tools never gets told it has one."
            )
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        } header: {
            SectionHeader("Injected context", count: config.context.enabledCount)
        }
    }

    func toggleRow(_ key: ContextKey) -> some View {
        Toggle(isOn: toggleBinding(key)) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(key.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if key.isConditional {
                        Label("Only added when the feature is live", systemImage: "bolt.horizontal")
                            .font(.caption2)
                            .foregroundStyle(CairnTheme.amber)
                    }
                }
                Spacer(minLength: 4)
                InfoButton(title: key.displayName, text: key.explainer)
            }
        }
        .tint(CairnTheme.amber)
    }

    func toggleBinding(_ key: ContextKey) -> Binding<Bool> {
        Binding(
            get: { config.context.value(key) },
            set: { config.context.setValue(key, $0) }
        )
    }

    /// The exact block, from the same call the stream uses. Preview and wire are one function so the
    /// text on screen cannot drift from the text that goes out.
    func previewSection(_ text: String) -> some View {
        Section("The system message Cairn sends") {
            if text.isEmpty {
                Text(
                    "Nothing. There is no system message in this conversation at all — your words go "
                        + "to the model with nothing added in front of them."
                )
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
            } else {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                Text(
                    "\(text.utf8.count) bytes, as one message at the head of the conversation. "
                        + "This is what goes on the wire, not an approximation of it."
                )
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
            }
        }
    }
}
