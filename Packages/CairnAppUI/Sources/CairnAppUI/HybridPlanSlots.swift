import Foundation
import CairnChatDomain

/// The rows the hybrid section edits, as pure functions over a `HybridPlan`.
///
/// Two slots always exist even when the plan holds none, so a half-built plan shows as two rows
/// plus the reason it cannot run rather than as one row and a dead button. Keeping the edits here
/// means the picker and a test read the same rule for what a tap does to the plan.
enum HybridPlanSlots {
    static let count = 2

    /// One row's candidate, or an unfinished empty row when the plan has not reached that index.
    static func slot(_ plan: HybridPlan, at index: Int) -> HybridCandidate {
        plan.candidates.indices.contains(index)
            ? plan.candidates[index]
            : HybridCandidate(engineID: "", modelID: "")
    }

    /// Choosing an engine also re-resolves its model, because a model name belongs to one engine
    /// only. Carrying a name across is how a server gets asked for a model it does not have.
    static func setting(
        _ plan: HybridPlan, engineAt index: Int, to engineID: String, model modelID: String
    ) -> HybridPlan {
        var next = padded(plan)
        next.candidates[index] = HybridCandidate(
            engineID: engineID,
            modelID: engineID.isEmpty ? "" : modelID
        )
        return next
    }

    static func setting(_ plan: HybridPlan, modelAt index: Int, to modelID: String) -> HybridPlan {
        var next = padded(plan)
        var chosen = next.candidates[index]
        chosen.modelID = modelID
        next.candidates[index] = chosen
        return next
    }

    /// Rows a turn could actually be built from — used for the writer picker, which may only be
    /// one of the pairs that is really chosen. Duplicates are collapsed here because a picker cannot
    /// show the same id twice; the plan itself still reports the duplicate as its own refusal.
    static func chosen(_ plan: HybridPlan) -> [HybridCandidate] {
        var seen: Set<String> = []
        return plan.candidates.filter { $0.isChosen && seen.insert($0.id).inserted }
    }

    /// The picker's selection. An empty tag means "let Cairn choose", which is the rule: remote
    /// first, an on-device writer only as the sequential fallback.
    static func synthesizerTag(of plan: HybridPlan) -> String { plan.synthesizer?.id ?? "" }

    static func setting(_ plan: HybridPlan, synthesizerTag tag: String) -> HybridPlan {
        var next = plan
        next.synthesizer = tag.isEmpty ? nil : plan.candidates.first { $0.id == tag }
        return next
    }

    private static func padded(_ plan: HybridPlan) -> HybridPlan {
        var next = plan
        while next.candidates.count < count {
            next.candidates.append(HybridCandidate(engineID: "", modelID: ""))
        }
        return next
    }
}
