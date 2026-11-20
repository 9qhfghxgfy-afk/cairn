import SwiftUI
import CairnChatDomain

/// The optional model-source tokens, as a Settings group.
///
/// They live below the Models group rather than inside it, because they are not a permission. The toggle
/// above them decides whether bytes may leave this phone at all; these rows decide whether Cairn introduces
/// itself to a source before asking for them. A person who grants the first and leaves both rows empty gets
/// every public model in the library, which is the state the app is designed to work in.
///
/// The group is absent when the app layer supplied no store. A field that cannot save is worse than no field:
/// it invites a paste, then either loses it silently or says "Saved" about a write that never happened.
extension SettingsView {
    @ViewBuilder
    var modelTokensSection: some View {
        if let modelTokens {
            Section {
                ForEach(ModelTokenKind.allCases) { kind in
                    ModelTokenRow(model: modelTokens, kind: kind)
                }
                if let notice = modelTokens.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(CairnTheme.stoneLight)
                        .accessibilityIdentifier("cairn.settings.token.notice")
                }
            } header: {
                Text("Model source tokens")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Both are optional. Every public model in the library downloads with neither. A token "
                            + "is what reaches a source that asks who is asking — a repository whose terms "
                            + "have to be accepted first, or a registry behind a proxy."
                    )
                    Text(
                        "A token is kept in this phone's own secure storage: not in Settings, not in a file "
                            + "Cairn exports, never shown back to you once saved. It is sent only to the host "
                            + "it was written for, and it is dropped at the first redirect to a different "
                            + "host. Clear the field and press Save to take it off this phone."
                    )
                }
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
            }
        }
    }
}
