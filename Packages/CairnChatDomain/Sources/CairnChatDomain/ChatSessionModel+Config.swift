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
    /// "Current turn" is the turn the path ends at — the newest question on screen — because that is the
    /// only turn a document or image block can honestly describe. A question still being typed is not
    /// something the sheet can know; for the turn it does describe, preview and wire come from the same
    /// call and stay byte-identical.
    public var injectedContextPreview: String {
        guard let provider = activeProvider else {
            return conversation.config.systemPrompt(in: contextEnvironment, turn: currentTurnContext)
        }
        // The same call the turn uses, tool block included: a preview that leaves the tool block out
        // would show a prompt the request does not send.
        let selection = toolSelection(for: provider)
        return systemPrompt(
            for: provider,
            selection: selection,
            format: toolRouting(for: provider).format,
            turn: turnContext(for: provider, history: path)
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

    /// The window this turn really has, when the engine holds less than the chat asked for.
    ///
    /// A chat configured for 32,768 tokens and pointed at an engine that holds 4,096 does not gain a
    /// bigger window by being configured: the setting says what the chat would like, the engine says
    /// what it has. Said beside the controls rather than left to a failed turn, because a number that
    /// quietly means something else is the kind of promise this app does not make.
    public var contextCeilingNote: String? {
        guard let ceiling = activeProvider?.contextTokenCeiling else { return nil }
        let asked = conversation.config.sampling.contextWindow ?? 0
        guard asked == 0 || asked > ceiling else { return nil }
        return "This engine holds about \(ceiling) tokens at once — older turns are dropped so the turn fits."
    }

    /// What a switch is asking for that this engine cannot do, in one line each.
    ///
    /// The switches stay live — a backend gets the tools through the prompt protocol, and a thinking
    /// switch costs nothing — but a control that promises a thing nobody performs reads as a broken
    /// app. So the composer says what will not appear, next to the switch that asked for it, instead of
    /// leaving an empty panel to be discovered.
    public var engineCapabilityNotes: [String] {
        guard let provider = activeProvider else { return [] }
        var notes: [String] = []
        if conversation.config.thinkingEnabled, !provider.capabilities.thinking {
            notes.append("\(provider.displayName) emits no reasoning trace, so Thinking adds nothing here.")
        }
        if conversation.config.toolToggle.isEnabled, !provider.capabilities.toolCalling {
            notes.append(
                "\(provider.displayName) is offered Tools as text, not as calls it can make; "
                    + "a tight window drops them first."
            )
        }
        return notes
    }

    public var currentTurnContext: TurnContext {
        if let provider = activeProvider { return turnContext(for: provider, history: path) }
        // No engine selected: state nothing about the backend rather than guessing, so the
        // capability line is left out instead of being wrong. Attachments are still reported, because
        // they are a fact about this conversation and not about a server.
        let grounding = Grounding.outcome(
            for: path, windowTokens: conversation.config.sampling.contextWindow
        )
        return TurnContext(
            fileCount: grounding.documentsConsidered,
            imageCount: ChatTree.currentTurnImages(in: path).count,
            passages: grounding.passages,
            contextTokens: conversation.config.sampling.contextWindow
        )
    }

    /// What this turn can do, read from the engine's declared capabilities — never from an
    /// assumption about what a model class usually supports.
    ///
    /// `history` is the path the turn will be sent with, so the attachment facts describe the same
    /// conversation the request will: the images of the newest user message, and the documents the
    /// retrieval actually searched. With no history both are zero, which is what a session with nothing
    /// in it means.
    func turnContext(
        for provider: any InferenceProvider,
        history: [ChatNode] = [],
        grounding: GroundingOutcome? = nil
    ) -> TurnContext {
        let capabilities = provider.capabilities
        let config = conversation.config
        let offered = toolSelection(for: provider)
        let resolved = grounding ?? Grounding.outcome(
            for: history, windowTokens: config.sampling.contextWindow
        )
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
            // The `Force Web Fetch` toggle in the sheet, read live: on a turn that really is being
            // offered a web tool. This used to be `false` with no input at all, which made the key in
            // the sheet a switch that switched nothing.
            webFetchActive: ContextAssembly.webFetchIsLive(
                toggles: config.context, offered: offered
            ),
            visionOn: capabilities.vision,
            // Documents counted by the retrieval pass, which counts distinct attachments rather than
            // passages: one file cut into six passages is still one file the user attached.
            fileCount: resolved.documentsConsidered,
            imageCount: ChatTree.currentTurnImages(in: history).count,
            passages: resolved.passages,
            contextTokens: config.sampling.contextWindow
        )
    }

    /// The grounding this conversation's current turn would be sent with — the passages, the sources,
    /// and how many passages did not fit. The sheet shows this so "what did my document contribute" is
    /// an answerable question rather than something buried in a prompt.
    public var currentGrounding: GroundingOutcome {
        Grounding.outcome(for: path, windowTokens: conversation.config.sampling.contextWindow)
    }

    /// The documents on this conversation's path, for the sheet's list.
    public var attachedDocuments: [ChatAttachment] {
        Attachments.documents(ChatTree.documents(in: path))
    }

    /// The images attached to the newest message on the path, whether or not this engine can see them.
    public var currentTurnImageCount: Int {
        ChatTree.currentTurnImages(in: path).count
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
