import SwiftUI
import CairnChatDomain

/// The header's outbound badge, and the rule that decides whether it stands.
///
/// **It stands before anything has been sent.** The badge used to appear only once a turn had used a tool,
/// which is the last moment a notice can be read — the query was already gone, and a badge that arrives after
/// the fact is a receipt rather than a warning. The condition worth noticing beforehand is the standing one:
/// this chat has its `Tools` chip up, the device has acknowledged that a tool may reach the public internet,
/// and the provider selected in Settings is somewhere beyond the user's own network. When all three are true,
/// something can leave, and the header says so.
///
/// A conversation that has already sent something keeps its badge for the rest of the conversation, which is
/// the older rule and still the right one: a search two turns ago is only visible afterwards, and that is
/// exactly when a badge that vanished would be useless.
extension ChatScreen {
    var outboundBadge: ToolsOutboundBadge {
        if session?.hasUsedWebTools == true {
            return ToolsOutboundBadge(usedWebTools: true)
        }
        guard let settings,
              session?.conversation.config.toolToggle.isEnabled == true,
              settings.settings.outboundWebAllowed else {
            return ToolsOutboundBadge(usedWebTools: false)
        }
        let provider = settings.settings.webSearch.activeProvider
        guard WebSearchBadgeRule.showsImmediately(
            profile: provider, webToolsEnabled: true
        ) else {
            return ToolsOutboundBadge(usedWebTools: false)
        }
        return ToolsOutboundBadge(
            usedWebTools: true,
            detail: WebSearchBadgeRule.detail(profile: provider)
        )
    }
}
