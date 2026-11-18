import Foundation

/// The tool surface of `ChatSessionModel`: what a turn is offered, how the system block is built
/// around that offer, and the drain that runs a multi-step tool turn.
///
/// One path builds the system block for every turn, tool turn or not, because the configuration
/// sheet previews that block character for character. A second path that added the tool block only
/// on the wire would make the preview a lie, which is the same failure P2 closed for system messages.
extension ChatSessionModel {

    /// The routing decision for one engine, read from that engine's declared capabilities and the
    /// chat's own switches — never from an assumption about what a model class usually supports.
    public func toolRouting(for provider: any InferenceProvider) -> ToolRouting {
        ToolRouting(
            toolToggle: conversation.config.toolToggle,
            capabilities: provider.capabilities,
            registry: toolRegistry,
            outboundWebAllowed: outboundWebAllowed
        )
    }

    /// The tools one turn offers, fitted to the chat's context budget when the user set one.
    ///
    /// A hybrid turn offers nothing, deliberately: `HybridEngine` asks several engines and has no
    /// place to run a call, so offering tools there would let a model write a call Cairn never
    /// executes — and a model that believes a tool answered is a model that will report an answer it
    /// never got. The chip says so instead.
    func toolSelection(for provider: any InferenceProvider) -> ToolSelection {
        let routing = toolRouting(for: provider)
        guard routing.offersTools, !conversation.mode.isHybrid else { return ToolSelection() }
        // With no configured window there is nothing to fit against, so the whole offerable set
        // travels — `offerableNames` has already removed anything this turn may not run.
        guard let window = conversation.config.sampling.contextWindow, window > 0 else {
            return routing.selection(withinWordBudget: .max, wordBudget: Self.wordCount)
        }
        // Words, not tokens: there is no tokenizer in this module, and an estimate shown as a token
        // count is a number the user reads as exact. A quarter of the window is what the block may
        // take; the conversation keeps the rest.
        return routing.selection(withinWordBudget: window / 4, wordBudget: Self.wordCount)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The one system block for a turn: the assembled context, then the tool block last. Both the
    /// sheet's preview and the wire come through here.
    ///
    /// `turn` is handed in by the streaming path so this block is built from the same `TurnContext` the
    /// request is described by — preview and wire cannot drift, because both are given the same value.
    /// When it is nil, the path the session is on is used, which is what a tool turn needs.
    func systemPrompt(
        for provider: any InferenceProvider,
        selection: ToolSelection,
        format: ToolCallingProtocol,
        turn: TurnContext? = nil
    ) -> String {
        let context = turn ?? turnContext(for: provider, history: path)
        let base = conversation.config.systemPrompt(in: contextEnvironment, turn: context)
        let block = selection.instruction(format: format)
        if block.isEmpty { return base }
        if base.isEmpty { return block }
        return base + "\n\n" + block
    }

    /// True once any turn in this conversation has had a tool reach the public internet.
    ///
    /// Read off the stored nodes rather than a session-scoped flag, so the badge survives a reopen and
    /// describes what actually happened in *this* conversation. That is the whole point of it: a user
    /// who armed tools and then stopped should still be able to see that a query left the phone.
    public var hasUsedWebTools: Bool {
        nodes.contains { $0.toolRun?.usedWebTools == true }
    }

    /// The tools this chat's chip would offer, for the composer's switch list — including the ones the
    /// outbound acknowledgement currently holds back, so the list explains itself instead of showing
    /// three tools that vanished.
    public var chipToolNames: [String] { conversation.config.toolToggle.enabledToolNames }

    /// Arms or disarms this chat's tools, and persists the chat so the chip survives a relaunch.
    public func setTools(_ toggle: ToolToggleSet) {
        var config = conversation.config
        config.toolToggle = toggle
        updateConfig(config)
    }

    /// One tool's own switch. Deliberately does not raise the chip: a user who turns one tool on in
    /// Settings still has to arm the chat.
    public func setTool(_ name: String, on: Bool) {
        var toggle = conversation.config.toolToggle
        toggle.setOn(name, on)
        setTools(toggle)
    }
}
