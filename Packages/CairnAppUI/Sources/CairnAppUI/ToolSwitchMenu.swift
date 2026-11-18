import SwiftUI
import CairnChatDomain

/// The per-tool switches behind the `Tools` chip.
///
/// A chip that means "all five" with no way to say "not the one that searches" is a single decision
/// wearing three tools. Here each tool is its own switch, and a web switch that the outbound
/// acknowledgement has not released stays disabled and says why — the state the user reaches by
/// choosing "only tools on this device" in the disclosure, which is a real state rather than a refusal.
struct ToolSwitchMenu: View {
    let session: ChatSessionModel
    let outboundAllowed: Bool

    var body: some View {
        Menu {
            ForEach(BuiltInTool.allNames, id: \.self) { name in
                Toggle(
                    isOn: Binding(
                        get: { session.conversation.config.toolToggle.isOn(name) },
                        set: { session.setTool(name, on: $0) }
                    )
                ) {
                    Label(Self.title(name), systemImage: Self.symbol(name))
                }
                .disabled(!outboundAllowed && BuiltInTool.isWebTool(name))
            }
        } label: {
            Image(systemName: "slider.horizontal.below.rectangle")
                .font(.caption)
                .padding(6)
                .background(Capsule().fill(CairnTheme.stone.opacity(0.16)))
                .foregroundStyle(CairnTheme.amber)
        }
        .accessibilityLabel("Tool switches")
    }

    static func title(_ name: String) -> String {
        switch name {
        case BuiltInTool.webSearch: return "Web search"
        case BuiltInTool.webFetch: return "Read a page"
        case BuiltInTool.wikiSearch: return "Wikipedia"
        case BuiltInTool.calculator: return "Calculator"
        case BuiltInTool.composeMail: return "Draft an email"
        default: return name
        }
    }

    static func symbol(_ name: String) -> String {
        switch name {
        case BuiltInTool.webSearch: return "magnifyingglass"
        case BuiltInTool.webFetch: return "doc.plaintext"
        case BuiltInTool.wikiSearch: return "book"
        case BuiltInTool.calculator: return "plus.minus"
        case BuiltInTool.composeMail: return "envelope"
        default: return "wrench"
        }
    }
}
