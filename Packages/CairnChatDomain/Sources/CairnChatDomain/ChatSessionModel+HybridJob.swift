import Foundation

/// Resolving a hybrid turn: which engines are on offer, which plan this chat runs, and the job
/// the engine will execute.
///
/// Split from the drain because "what could answer" and "run it" are different jobs, and because
/// the picker and the turn must read the same resolution — a plan the sheet shows and a plan the
/// turn actually runs cannot be allowed to disagree.
extension ChatSessionModel {

    /// Every registered engine with the model it would answer with.
    public var hybridEngineOptions: [HybridEngineOption] {
        registeredEngines.map { provider in
            HybridEngineOption(
                engineID: provider.id,
                modelID: defaultModel(forEngine: provider.id),
                networkClass: provider.networkClass
            )
        }
    }

    /// Engines come from the live registry when the app wires one, so a server profile saved or
    /// removed changes what a hybrid turn can offer. The static list keeps tests deterministic,
    /// sorted because a dictionary's order is not.
    var registeredEngines: [any InferenceProvider] {
        if let registry { return registry.providers }
        return providers.values.sorted { $0.id < $1.id }
    }

    func engine(id: String) -> (any InferenceProvider)? {
        registry?.provider(id: id) ?? providers[id]
    }

    /// The name a picker shows for one engine. An engine that is not registered right now is named
    /// by its id rather than guessed at, because inventing a name for a server the user cannot see
    /// is how a row ends up promising an answer nothing will give.
    public func engineDisplayName(_ engineID: String) -> String {
        engine(id: engineID)?.displayName ?? engineID
    }

    /// The model this engine would be asked for: what was read from it, then what the app
    /// remembers it was last used with, then what the chat currently has selected. Never a name
    /// carried over from a different engine.
    public func defaultModel(forEngine engineID: String) -> String {
        if let read = modelsByEngine[engineID]?.first?.id, !read.isEmpty { return read }
        if let profileID = RemoteEngineID.parse(engineID),
           let remembered = selection?.lastModel(forProfile: profileID), !remembered.isEmpty {
            return remembered
        }
        if engineID == selectedProviderID, !selectedModelID.isEmpty { return selectedModelID }
        return ""
    }

    /// Reads one engine's models so the picker can offer real names for a server the chat is not
    /// currently pointed at. A failure leaves an empty list, which the picker reports rather than
    /// papering over — it is not this turn's error.
    public func loadModels(forEngine engineID: String) async {
        guard let provider = engine(id: engineID) else {
            modelsByEngine[engineID] = []
            return
        }
        do {
            modelsByEngine[engineID] = try await provider.models()
        } catch {
            modelsByEngine[engineID] = []
        }
    }

    /// The plan this chat runs: what the user chose when it is runnable, otherwise a sensible one
    /// built from what is registered right now.
    public var hybridPlan: HybridPlan {
        if let stored = conversation.config.hybrid, stored.isRunnable { return stored }
        return HybridPlan.defaultPlan(from: hybridEngineOptions)
    }

    /// Why this chat cannot run a hybrid turn yet, or nil when it can.
    public var hybridBlockReason: String? {
        let plan = hybridPlan
        if let issue = plan.issue { return issue.reasonText }
        if let missing = plan.candidates.first(where: { engine(id: $0.engineID) == nil }) {
            return "Engine \(missing.engineID) is not registered right now."
        }
        return nil
    }

    public var canRunHybridTurn: Bool { hybridBlockReason == nil }

    /// The turn to run, or nil with `hybridBlockReason` in `lastError`.
    func makeHybridJob(assistantNodeID: UUID) -> HybridJob? {
        let plan = hybridPlan
        guard plan.isRunnable else {
            lastError = plan.issue?.reasonText ?? HybridPlanIssue.needsTwoCandidates.reasonText
            return nil
        }

        var classes: [NetworkClass] = []
        for candidate in plan.candidates {
            guard let provider = engine(id: candidate.engineID) else {
                lastError = "Engine \(candidate.engineID) is not registered right now, "
                    + "so this hybrid turn cannot start."
                return nil
            }
            classes.append(provider.networkClass)
        }

        let history = ChatTree.visiblePath(nodes: nodes, activeLeafID: assistantNodeID)
        var requests: [GenerationRequest] = []
        for candidate in plan.candidates {
            guard let provider = engine(id: candidate.engineID) else { continue }
            requests.append(generationRequest(to: provider, modelID: candidate.modelID, history: history))
        }

        return HybridJob(
            mode: conversation.mode,
            plan: plan,
            requests: requests,
            providers: Dictionary(
                registeredEngines.map { ($0.id, $0) },
                uniquingKeysWith: { _, last in last }
            ),
            networkClasses: classes,
            synthesis: makeSynthesisJob(plan: plan, classes: classes, history: history),
            residency: residency
        )
    }

    /// One assembly path for every side of a hybrid turn: the system block is built from the
    /// engine being asked, which is the same call the configuration sheet previews. Two places
    /// each prepending a persona is the duplicate-system-message bug P2 closed, so there is one.
    func generationRequest(
        to provider: any InferenceProvider,
        modelID: String,
        history: [ChatNode]
    ) -> GenerationRequest {
        let config = conversation.config
        return GenerationRequest(
            modelID: modelID,
            messages: ChatTree.messages(
                for: history,
                systemPrompt: config.systemPrompt(in: contextEnvironment, turn: turnContext(for: provider))
            ),
            config: config
        )
    }

    /// The synthesizer stage exists only for a synthesized turn. Parallel mode deliberately has
    /// none: its answer is the two drafts side by side, not a third opinion nobody asked for.
    private func makeSynthesisJob(
        plan: HybridPlan,
        classes: [NetworkClass],
        history: [ChatNode]
    ) -> HybridSynthesisJob? {
        guard conversation.mode == .hybridSynthesized else { return nil }
        guard let chosen = HybridScheduling.resolveSynthesizer(plan: plan, networkClasses: classes),
              let provider = engine(id: chosen.engineID) else { return nil }
        return HybridSynthesisJob(
            candidate: chosen,
            provider: provider,
            networkClass: provider.networkClass,
            question: Self.question(in: history),
            persona: conversation.config.persona,
            config: conversation.config
        )
    }

    /// The question the synthesizer is asked to unify: the user turn this answer belongs to, and
    /// nothing earlier. History stays with the providers that already saw it.
    static func question(in history: [ChatNode]) -> String {
        history.last(where: { $0.role == .user })?.text ?? ""
    }
}