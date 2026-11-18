import SwiftUI
import CairnChatDomain

/// The hybrid rows of the per-chat sheet: which two engine + model pairs answer, which one writes
/// the unified answer, and — said inline, next to the row that caused it — why the plan cannot run.
///
/// A candidate is a **pair**, not an engine: one server answering with two models is two legitimate
/// sides, and the same pair twice is a mistake the sheet refuses rather than sends. Refusal text
/// comes from `HybridPlan.issue`, so the words a user reads are the words the turn itself would
/// refuse with — one rule, one wording.
struct HybridConfigSection: View {
    let session: ChatSessionModel
    @Binding var plan: HybridPlan

    var body: some View {
        Section {
            ForEach(0..<HybridPlanSlots.count, id: \.self) { index in
                candidateRow(index)
            }
            writerRow
            if let refusal = refusalText {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(CairnTheme.rust)
            }
        } header: {
            Text("Hybrid turn")
        } footer: {
            Text(footerText)
        }
    }

    // MARK: - Rows

    private func candidateRow(_ index: Int) -> some View {
        let slot = HybridPlanSlots.slot(plan, at: index)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Candidate \(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CairnTheme.stoneLight)

            Picker("Engine", selection: Binding(
                get: { slot.engineID },
                set: { engineID in
                    plan = HybridPlanSlots.setting(
                        plan, engineAt: index, to: engineID,
                        model: session.defaultModel(forEngine: engineID)
                    )
                }
            )) {
                Text("no engine chosen").tag("")
                ForEach(engineChoices, id: \.id) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }

            Picker("Model", selection: Binding(
                get: { slot.modelID },
                set: { modelID in
                    plan = HybridPlanSlots.setting(plan, modelAt: index, to: modelID)
                }
            )) {
                Text(modelPlaceholder(for: slot)).tag("")
                ForEach(modelChoices(for: slot), id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
        // Read the engine's own model list so the picker offers real names for a server this chat
        // is not pointed at. A failure leaves the row empty, which the placeholder says out loud.
        .task(id: slot.engineID) {
            let engineID = slot.engineID
            guard !engineID.isEmpty else { return }
            await session.loadModels(forEngine: engineID)
        }
    }

    private var writerRow: some View {
        Picker("Writer", selection: Binding(
            get: { HybridPlanSlots.synthesizerTag(of: plan) },
            set: { tag in plan = HybridPlanSlots.setting(plan, synthesizerTag: tag) }
        )) {
            Text("Cairn chooses — remote first").tag("")
            ForEach(HybridPlanSlots.chosen(plan)) { candidate in
                Text(title(of: candidate)).tag(candidate.id)
            }
        }
    }

    // MARK: - Choices and wording

    private var engineChoices: [(id: String, title: String)] {
        var seen: Set<String> = []
        return session.hybridEngineOptions.compactMap { option in
            guard !option.engineID.isEmpty, seen.insert(option.engineID).inserted else { return nil }
            let name = session.engineDisplayName(option.engineID)
            return (option.engineID, option.isOnDevice ? name : "\(name) — remote")
        }
    }

    private func modelChoices(for slot: HybridCandidate) -> [String] {
        guard !slot.engineID.isEmpty else { return [] }
        let read = session.modelsByEngine[slot.engineID]?.map(\.id) ?? []
        // A pair already chosen has to stay representable even before this engine's list has been
        // read, or the picker would silently drop the value the chat is holding.
        guard !slot.modelID.isEmpty, !read.contains(slot.modelID) else { return read }
        return [slot.modelID] + read
    }

    private func modelPlaceholder(for slot: HybridCandidate) -> String {
        if slot.engineID.isEmpty { return "choose an engine first" }
        if (session.modelsByEngine[slot.engineID] ?? []).isEmpty { return "no model read from this engine" }
        return "choose a model"
    }

    private func title(of candidate: HybridCandidate) -> String {
        "\(session.engineDisplayName(candidate.engineID)) · \(candidate.modelID)"
    }

    /// The first reason this chat cannot run a hybrid turn: the plan's own issue first, then an
    /// engine that stopped being registered after the plan was saved.
    private var refusalText: String? {
        if let issue = plan.issue { return issue.reasonText }
        return session.hybridBlockReason
    }

    private var footerText: String {
        "A hybrid turn asks both pairs the same question and keeps one assistant node holding both "
            + "drafts. Two on-device pairs take turns with the model released between them unless this "
            + "device reports measured room for both, and the writer defaults to the remote side."
    }
}
