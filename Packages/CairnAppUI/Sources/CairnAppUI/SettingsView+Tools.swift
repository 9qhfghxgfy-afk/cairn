import SwiftUI
import CairnChatDomain

/// The tools half of Settings: the acknowledgement that lets a tool reach the public internet, and the way
/// into the Web Search screen.
///
/// Both live here rather than in a chat because both are decisions about the device, not about one
/// conversation: they persist across chats, they are reversible, and a user who armed a chat from its
/// composer should be able to find the switch again and turn it back off. The per-tool switches stay
/// with the `Tools` chip, since which tools one conversation may use is a per-conversation choice.
///
/// The single SearXNG address field that used to sit here is gone. It could not say which provider was
/// active, could not hold a credential, could not record what had been agreed to, and could not be tested —
/// and its value is imported into a provider row the first time the settings row that holds it is read, so
/// nothing typed into it is lost.
extension SettingsView {

    @ViewBuilder
    var toolsSection: some View {
        Section {
            InfoRow(
                key: .webToolsOutbound,
                caption: "Search, page reading and Wikipedia send a query or an address off this device."
            ) {
                Toggle(
                    isOn: Binding(
                        get: { theme.settings.outboundWebAllowed },
                        set: { theme.setOutboundWebAllowed($0) }
                    )
                ) {
                    Text("Web tools may reach the internet")
                }
                .tint(CairnTheme.amber)
            }
        } header: {
            Text("Tools")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "One provider answers a search: the one picked under Web Search. If it fails, searching "
                        + "fails with the reason named — Cairn never sends the same words to a different "
                        + "provider, because a result from a provider you did not choose is a disclosure you "
                        + "cannot see. Running your own SearXNG instance removes the third party from the "
                        + "request entirely, and a plain http address is accepted for one on your own "
                        + "network."
                )
                Text(
                    "The calculator and mail drafts need no acknowledgement: they run on this device and "
                        + "open nothing but a draft for you to send."
                )
                if let error = theme.lastError {
                    Text(error).foregroundStyle(CairnTheme.rust)
                }
            }
            .font(.caption)
            .foregroundStyle(CairnTheme.stoneLight)
        }
        // The provider row sits in its own section so its `(i)` has a header to rest on. A navigation link
        // makes the entire row its tap target, and a button inside that label is a button the link may take
        // the tap from. The header names the same thing the row opens.
        Section {
            if let webSearch {
                // A screen of its own rather than one more field: which provider answers, whether it has been
                // agreed to, and whether it answers at all are three questions a text box cannot hold.
                NavigationLink {
                    WebSearchSettingsScreen(model: webSearch)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Web Search").font(.subheadline)
                        Text(webSearch.active.displayName)
                            .font(.caption)
                            .foregroundStyle(CairnTheme.stoneLight)
                    }
                }
            } else {
                // No model wired means no vault and no tester in this build — so the row reports what is set
                // instead of opening a screen that could not save a row or test one.
                LabeledContent("Search provider") {
                    Text(theme.settings.activeWebSearchProvider.displayName)
                }
            }
        } header: {
            InfoSectionHeader("Search provider", key: .webSearchProvider)
        }
    }
}
