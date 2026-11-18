import SwiftUI
import CairnChatDomain

/// The composer's two switches: `Thinking` and `Tools`.
///
/// Both belong to one conversation and both are written through the session, so what the chip shows and
/// what the stored conversation says are the same fact. `Tools` ships **down**, and the first tap that
/// would raise it while the outbound acknowledgement is still down asks the question first: a tool that
/// sends a query to a public service is not armed by an unlabeled tap. Both ways out of that question
/// are offered, because "no, not the internet" should still leave the user the calculator.
public struct ComposerChips: View {
    private let session: ChatSessionModel
    /// The settings store when one is wired. The acknowledgement is app-wide and has to outlive the
    /// chat that asked for it, so it is recorded there and not only on this session.
    private var theme: ThemeModel?
    @State private var askingAboutOutbound = false

    public init(session: ChatSessionModel, theme: ThemeModel? = nil) {
        self.session = session
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 8) {
            thinkingChip
            Button(action: toggleTools) {
                chip("Tools", on: toolsAreUp, symbol: "wrench.and.screwdriver")
            }
            .accessibilityLabel("Tools")
            .accessibilityValue(toolsAreUp ? "on" : "off")

            if toolsAreUp {
                ToolSwitchMenu(
                    session: session,
                    outboundAllowed: session.outboundWebAllowed
                )
            }
            Spacer(minLength: 0)
        }
        .confirmationDialog(
            "Tools can reach the public internet",
            isPresented: $askingAboutOutbound,
            titleVisibility: .visible
        ) {
            Button("Allow web tools") { arm(withWeb: true) }
            Button("Only tools on this device") { arm(withWeb: false) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                "A web tool sends the search query or the address you name to a service you did not "
                    + "choose, and what comes back joins this conversation. Cairn keeps a badge up while "
                    + "any of it leaves the phone, and the switch list next to the chip turns each tool "
                    + "off. Arithmetic and mail drafts need no acknowledgement — they run here."
            )
        }
    }

    private var toolsAreUp: Bool { session.conversation.config.toolToggle.isEnabled }

    private func toggleTools() {
        if toolsAreUp {
            session.setTools(.off)
            return
        }
        // Already acknowledged once, app-wide: the chip is a per-chat decision and does not have to ask
        // again, which is what makes the second conversation's first tap a tap.
        if session.outboundWebAllowed { arm(withWeb: true); return }
        askingAboutOutbound = true
    }

    private func arm(withWeb: Bool) {
        if withWeb {
            theme?.setOutboundWebAllowed(true)
            session.outboundWebAllowed = true
            session.setTools(.default)
        } else {
            session.setTools(.localOnly)
        }
    }

    private var thinkingChip: some View {
        Button(action: { session.setThinking(!session.conversation.config.thinkingEnabled) }) {
            chip("Thinking", on: session.conversation.config.thinkingEnabled, symbol: "brain")
        }
        .accessibilityLabel("Thinking")
        .accessibilityValue(thinkingSpokenState)
    }

    /// Said out loud rather than shown as a dimmer chip: a reasoning panel that stays empty next to an
    /// "on" switch reads as a broken app unless the switch has already said what this backend does.
    private var thinkingSpokenState: String {
        guard session.conversation.config.thinkingEnabled else { return "off" }
        return session.reasoningSupported
            ? "on"
            : "on, but this server has not been seen to return reasoning, so nothing extra will appear"
    }

    private func chip(_ title: String, on: Bool, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2)
            Text(title).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(on ? CairnTheme.amber.opacity(0.22) : CairnTheme.stone.opacity(0.16))
        )
        .overlay(
            Capsule().stroke(on ? CairnTheme.amber.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .foregroundStyle(on ? CairnTheme.amber : CairnTheme.stoneLight)
    }
}
