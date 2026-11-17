import Foundation

/// Which engines answer a hybrid turn, and which one writes the unified answer.
///
/// Stored inside `ChatConfig` as one optional field of the chat's own configuration blob, so
/// a chat written before M4 decodes with `hybrid == nil` and Cairn chooses a plan from the
/// engines that exist right now rather than inventing one out of nothing.
public struct HybridPlan: Sendable, Equatable, Codable {
    /// Declared order is meaningful: candidate 0 is the primary whose answer stands on its
    /// own in the node's text when a turn is compared rather than synthesized.
    public var candidates: [HybridCandidate]
    /// `nil` means "let Cairn choose", which resolves to the remote candidate — the
    /// synthesizer rule is remote first, and on-device only as a sequential fallback.
    public var synthesizer: HybridCandidate?

    public init(
        candidates: [HybridCandidate] = [],
        synthesizer: HybridCandidate? = nil
    ) {
        self.candidates = candidates
        self.synthesizer = synthesizer
    }

    public var candidateCount: Int { candidates.count }

    /// The first thing wrong with this plan, or nil when it can run.
    public var issue: HybridPlanIssue? {
        if candidateCount < 2 { return .needsTwoCandidates }
        if candidates.contains(where: { !$0.isChosen }) { return .incompleteCandidate }
        if candidates.count != Set(candidates.map(\.id)).count { return .duplicateCandidate }
        if let synthesizer, !synthesizer.isChosen { return .incompleteCandidate }
        return nil
    }

    public var isRunnable: Bool { issue == nil }

    /// A plan worth running from what is actually registered: a remote side and an on-device
    /// side when both exist, because comparing a phone against a server is the turn this
    /// feature exists for. Otherwise the first two distinct engines.
    public static func defaultPlan(from options: [HybridEngineOption]) -> HybridPlan {
        var chosen: [HybridCandidate] = []
        var seen: Set<String> = []

        func take(_ option: HybridEngineOption) {
            guard chosen.count < 2, option.isValidPair, !seen.contains(option.pairKey) else { return }
            seen.insert(option.pairKey)
            chosen.append(HybridCandidate(engineID: option.engineID, modelID: option.modelID))
        }

        if let remote = options.first(where: { !$0.isOnDevice }),
           let local = options.first(where: { $0.isOnDevice }) {
            take(remote)
            take(local)
        } else {
            for option in options where option.isValidPair { take(option) }
        }
        return HybridPlan(candidates: chosen, synthesizer: nil)
    }
}

/// Why a hybrid plan cannot run, in words the picker can show instead of a dead button.
public enum HybridPlanIssue: String, Sendable, Equatable, CaseIterable {
    case needsTwoCandidates
    case incompleteCandidate
    case duplicateCandidate

    public var reasonText: String {
        switch self {
        case .needsTwoCandidates:
            return "A hybrid turn needs two candidates. Add a second engine and model in this chat's settings."
        case .incompleteCandidate:
            return "A hybrid row is missing its engine or its model."
        case .duplicateCandidate:
            return "Both hybrid candidates are the same engine and model."
        }
    }
}

private extension HybridEngineOption {
    var pairKey: String { "\(engineID)|\(modelID)" }
    var isValidPair: Bool { !engineID.isEmpty && !modelID.isEmpty }
}