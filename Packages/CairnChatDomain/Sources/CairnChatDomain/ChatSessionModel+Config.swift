import Foundation

/// The configuration surface of `ChatSessionModel` — the per-chat knobs (§3.2) and the injected
/// context (§3.3).
///
/// Split out because "editing settings" and "running a turn" are different jobs on the same object,
/// and because the preview the sheet renders has to be produced by the same call the stream uses.
/// One function, `injectedContextPreview`, is therefore the seam both sides read.
extension ChatSessionModel {

    /// The exact block this chat would inject on the current turn. The configuration sheet shows
    /// this live, character for character, as toggles move.
    public var injectedContextPreview: String {
        guard let provider = activeProvider else {
            return conversation.config.systemPrompt(in: contextEnvironment, turn: currentTurnContext)
        }
        // The same call the turn uses, tool block included: a preview that leaves the tool block out
        // would show a prompt the request does not send.
        let selection = toolSelection(for: provider)
        return systemPrompt(
            for: provider, selection: selection, format: toolRouting(for: provider).format
        )
    }

    /// The knobs the engine in use will read. The sheet renders from this and the encoder filters
    /// with it, so a control that the request would drop is never offered. With no engine selected
    /// nothing is claimed: the sheet offers nothing rather than guessing.
    public var samplingSupport: SamplingSupport {
        activeProvider?.samplingSupport ?? .none
    }

    /// Whether the selected engine has declared it emits reasoning.
    ///
    /// The `Thinking` chip reads this to say what will actually happen: a chip up against a backend
    /// that has never produced a reasoning field still shows no panel, and the chip should have said so
    /// instead of letting the empty panel read as a fault.
    public var reasoningSupported: Bool { activeProvider?.capabilities.thinking ?? false }

    public var currentTurnContext: TurnContext {
        if let provider = activeProvider { return turnContext(for: provider) }
        // No engine selected: state nothing about the backend rather than guessing, so the
        // capability line is left out instead of being wrong.
        return TurnContext(contextTokens: conversation.config.sampling.contextWindow)
    }

    /// What this turn can do, read from the engine's declared capabilities — never from an
    /// assumption about what a model class usually supports.
    func turnContext(for provider: any InferenceProvider) -> TurnContext {
        let capabilities = provider.capabilities
        let config = conversation.config
        let offered = toolSelection(for: provider)
        return TurnContext(
            backendLabel: Self.backendLabel(for: provider),
            onDevice: provider.networkClass == .onDevice,
            streaming: capabilities.streaming,
            // "On" only when the user asked for it and this backend really produces it; a reasoning
            // panel may not be promised to a backend that has not been seen to emit one.
            thinkingOn: config.thinkingEnabled && capabilities.thinking,
            // Tools are "active" only when something is actually offered to this engine: a chip that
            // is up against a registry with no tools, or a hybrid turn that cannot run a call, gets no
            // tool line — and a capability line claiming a tool the model was never given teaches it
            // to invent one.
            toolsActive: !offered.isEmpty,
            toolNames: ToolPromptBlock.names(offered.definitions),
            webFetchActive: false,
            visionOn: capabilities.vision,
            contextTokens: config.sampling.contextWindow
        )
    }

    /// A class of backend, never a profile name or address: the model does not need to know which
    /// machine the user owns, and the user should not have to reason about that leaving the device.
    private static func backendLabel(for provider: any InferenceProvider) -> String {
        switch provider.networkClass {
        case .onDevice:
            return "a model running on this device, so nothing of this conversation reaches a server"
        case .privateLan, .privateVPN:
            return "a model on a server the user runs on their own network"
        case .publicInternet:
            return "a model on a public internet service the user chose"
        }
    }

    /// Applies an edited configuration and persists the conversation row, so a knob moved in the
    /// sheet is true for the next turn and after a relaunch.
    /// The composer's `Thinking` chip: ask this backend for reasoning, and say nothing about it on a
    /// backend that has not been seen to emit any (`TurnContext.thinkingOn` ANDs this with the
    /// engine's declared capability, so the chip cannot promise a panel that never fills).
    public func setThinking(_ on: Bool) {
        var config = conversation.config
        guard config.thinkingEnabled != on else { return }
        config.thinkingEnabled = on
        updateConfig(config)
    }

    public func updateConfig(_ config: ChatConfig) {
        var updated = conversation
        updated.config = config
        updated.updatedAt = Date()
        do {
            try store.saveConversation(updated)
            conversation = updated
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// "Reset to Defaults": the chat takes the current baseline wholesale, which un-does every
    /// per-chat override rather than blending the baseline over the top of them.
    public func resetConfigToDefaults(_ defaults: ChatConfig) {
        updateConfig(defaults)
    }
}
