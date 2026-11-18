import SwiftUI
import CairnChatDomain

/// The tools half of Settings: the acknowledgement that lets a tool reach the public internet, and the
/// address of the user's own search instance.
///
/// Both live here rather than in a chat because both are decisions about the device, not about one
/// conversation: they persist across chats, they are reversible, and a user who armed a chat from its
/// composer should be able to find the switch again and turn it back off. The per-tool switches stay
/// with the `Tools` chip, since which tools one conversation may use is a per-conversation choice.
extension SettingsView {

    var toolsSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { theme.settings.outboundWebAllowed },
                    set: { theme.setOutboundWebAllowed($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Web tools may reach the internet").font(.subheadline)
                    Text(
                        "Search, page reading and Wikipedia send a query or an address off this device."
                    )
                    .font(.caption)
                    .foregroundStyle(CairnTheme.stoneLight)
                }
            }
            .tint(CairnTheme.amber)

            LabeledContent("Search endpoint") {
                TextField(
                    "Your SearXNG address",
                    text: Binding(
                        get: { theme.settings.searxngURL ?? "" },
                        set: { theme.setSearXNGURL($0) }
                    )
                )
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            }
        } header: {
            Text("Tools")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "With an address set, a search goes only to that instance, and a plain http address "
                        + "is allowed for it because it is on your own network. With none set, search "
                        + "uses Cairn's built-in keyless endpoint — a public service you did not choose "
                        + "— unless this chat is on Ollama Cloud with a saved key, in which case it uses "
                        + "Ollama's own search. Whichever ran is named in the result, and a badge stays "
                        + "up while anything has left the phone."
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
    }
}
