import SwiftUI
import CairnChatDomain

/// The composer's two switches: `Thinking` and `Tools`.
///
/// Both belong to one conversation and both are written through the session, so what the chip shows and
/// what the stored conversation says are the same fact. `Tools` ships **down**, and one tap raises it —
/// the whole point of the chip. The outbound acknowledgement is a real requirement and it is still
/// asked, but it travels **with** the chip rather than in front of it: a tap that opened a question and
/// left the chip unfilled read, on a phone, as a button that does not work, and a dialog dismissed by
/// reflex left the chat unarmed with nothing to show for the tap. Both ways out of the question are still
/// offered, because "no, not the internet" should leave the user the calculator.
public struct ComposerChips: View {
    private let session: ChatSessionModel
    /// The settings store when one is wired. The acknowledgement is app-wide and has to outlive the
    /// chat that asked for it, so it is recorded there and not only on this session.
    private var theme: ThemeModel?
    @Environment(\.cairnTokens) private var tokens
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
                "The chip is already up: this chat has its tools. A web tool sends the search query or the "
                    + "address you name to a service you did not choose, and what comes back joins this "
                    + "conversation. Cairn keeps a badge up while any of it leaves the phone, and the "
                    + "switch list next to the chip turns each tool off. Arithmetic and mail drafts need no "
                    + "acknowledgement — they run here, and stay up whichever way you answer."
            )
        }
    }

    private var toolsAreUp: Bool { session.conversation.config.toolToggle.isEnabled }

    /// One tap, one meaning: up, or down.
    ///
    /// The decision is the domain's (`ToolChipRule`), so the chip cannot grow an opinion of its own about
    /// what the backend claims to support or whether a disclosure has been answered yet. Nothing about a
    /// backend can swallow a tap: a server with no native tool calling is still given the tools, through
    /// `PromptToolProtocol`.
    private func toggleTools() {
        switch ToolChipRule.tap(
            chipIsUp: toolsAreUp,
            outboundWebAllowed: session.outboundWebAllowed
        ) {
        case .disarm:
            session.setTools(.off)
        case .arm(asksAboutWeb: let asksAboutWeb):
            // `.armed`, never `.default`: the shipped default has the chip down, so writing it here would
            // be a tap that changes nothing — which is the bug this path had.
            session.setTools(.armed)
            if asksAboutWeb { askingAboutOutbound = true }
        }
    }

    /// The two honest answers to the outbound question. The chip is already up when this is asked, so
    /// "only tools on this device" narrows what the chip means rather than undoing the tap.
    private func arm(withWeb: Bool) {
        if withWeb {
            theme?.setOutboundWebAllowed(true)
            session.outboundWebAllowed = true
            session.setTools(.armed)
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

    /// Painted from the theme rather than from the shipped constants: the chip is the one place a user
    /// looks to check whether the theme arrived, and a fixed amber in a Dusk conversation answers "no".
    private func chip(_ title: String, on: Bool, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2)
            Text(title).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(on ? tokens.accent.opacity(0.22) : tokens.onCanvasMuted.opacity(0.16))
        )
        .overlay(
            Capsule().stroke(
                on ? tokens.accent.opacity(0.6) : tokens.onCanvasMuted.opacity(0.24),
                lineWidth: 1
            )
        )
        .foregroundStyle(on ? tokens.accent : tokens.onCanvasMuted)
    }
}
