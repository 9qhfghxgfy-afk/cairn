import Foundation

/// Everything one hybrid turn ends with. The single assistant node is written from this, so the
/// node's text, its drafts, and its provenance can never disagree.
public struct HybridTurnOutcome: Sendable, Equatable {
    public var drafts: [CandidateDraft]
    /// `nil` in Parallel mode, where no synthesizer runs.
    public var synthesis: SynthesisOutcome?
    public var provenance: HybridProvenance
    public var state: NodeState
    /// The text to store on the node.
    ///
    /// Synthesized turns store the unified answer. Parallel turns store the primary candidate's
    /// answer — and if the primary candidate failed while another side answered, the first
    /// surviving answer stands in, so the next turn in this branch still reads a real assistant
    /// message rather than a hole.
    public var primaryText: String

    public init(
        drafts: [CandidateDraft],
        synthesis: SynthesisOutcome?,
        provenance: HybridProvenance,
        wasCancelled: Bool
    ) {
        let ordered = drafts.sorted { $0.order < $1.order }
        self.drafts = ordered
        self.synthesis = synthesis
        self.provenance = provenance
        self.primaryText = Self.choosePrimaryText(synthesis: synthesis, drafts: ordered)
        self.state = Self.chooseState(
            drafts: ordered,
            synthesis: synthesis,
            wasCancelled: wasCancelled
        )
    }

    static func choosePrimaryText(synthesis: SynthesisOutcome?, drafts: [CandidateDraft]) -> String {
        let unified = synthesis?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !unified.isEmpty { return unified }
        if let answered = drafts.first(where: { $0.answered }) { return answered.text }
        // Stopped or cancelled turns keep whatever partial text landed, as every other turn does.
        if let partial = drafts.first(where: { !$0.text.isEmpty }) { return partial.text }
        return ""
    }

    static func chooseState(
        drafts: [CandidateDraft],
        synthesis: SynthesisOutcome?,
        wasCancelled: Bool
    ) -> NodeState {
        if wasCancelled { return .cancelled }
        if let synthesis {
            if synthesis.answered { return .complete }
            let partial = synthesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // `.interrupted` means the unified answer itself stopped short: the node shows the
            // writer's own unfinished words, so it must say they are unfinished.
            if !partial.isEmpty { return .interrupted }
            // The writer produced nothing. A draft that did answer then stands as this turn's
            // content — a different text, honestly attributed to the side that wrote it — and with
            // nothing at all the turn failed and says so.
            return drafts.contains(where: \.answered) ? .complete : .failed
        }
        return drafts.contains(where: { $0.answered }) ? .complete : .failed
    }
}