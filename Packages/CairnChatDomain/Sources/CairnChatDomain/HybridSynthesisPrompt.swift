import Foundation

/// The synthesizer's own prompt, and the only payload it is given.
///
/// Deliberately narrow: the question, the drafts, and nothing else. The conversation's earlier
/// turns stay out, so choosing a second provider for a hybrid turn does not quietly send that
/// provider a transcript it was never asked to hold. The chat's persona is kept, because that
/// engine already receives it on every ordinary turn.
public enum HybridSynthesisPrompt {

    /// Written from scratch for Cairn. It asks for agreements, disagreements, and unsupported
    /// claims, and it forbids inventing reasoning a candidate never showed — the same rule the
    /// reasoning panel already obeys.
    public static let instruction = """
        You are given one question and several candidate answers to it. Write one answer.

        Work in this order:
        1. Agreements: what the candidates all say.
        2. Disagreements: where they conflict, stated plainly.
        3. Unsupported: anything one candidate asserts that none of the others back up.
        4. One unified answer that keeps only what the candidates support.

        Use only what the candidates contain. Do not guess how a candidate arrived at its answer, \
        and do not describe reasoning it did not show. A candidate that failed or came back empty \
        contributed nothing; say so rather than covering for it.
        """

    public static func systemText(persona: String) -> String {
        let voice = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voice.isEmpty else { return instruction }
        return voice + "\n\n" + instruction
    }

    /// The drafts, in declared order, each named by the engine that produced it. A failed draft
    /// is listed with its failure rather than omitted, so the synthesizer cannot silently invent
    /// the missing side.
    public static func draftsBlock(_ drafts: [CandidateDraft]) -> String {
        drafts.sorted { $0.order < $1.order }.enumerated().map { offset, draft in
            let attribution = [draft.sourceLabel, draft.modelID]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return "Candidate \(offset + 1) — \(attribution):\n\(content(of: draft))"
        }.joined(separator: "\n\n")
    }

    /// One side's text as the writer should read it. A side that failed or stopped is labelled as
    /// one **even when it got part-way**: an unfinished answer shown bare reads as a finished one,
    /// and the writer would then unify around a claim nobody actually completed.
    static func content(of draft: CandidateDraft) -> String {
        let body = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = draft.failure ?? "no reason was given"
        switch draft.state {
        case .failed:
            return body.isEmpty
                ? "(no answer — \(reason))"
                : "\(body)\n[This side failed before finishing: \(reason)]"
        case .cancelled, .interrupted:
            return body.isEmpty
                ? "(no answer — stopped before producing any text)"
                : "\(body)\n[This side was stopped before finishing]"
        case .streaming, .complete:
            return body.isEmpty ? "(no answer — nothing was produced)" : body
        }
    }

    public static func userText(question: String, drafts: [CandidateDraft]) -> String {
        "Question:\n\(question)\n\nCandidates:\n\(draftsBlock(drafts))"
    }

    /// Exactly two messages: the instruction as system, the question plus drafts as user. Any
    /// more than that would mean history going somewhere the user did not choose.
    public static func request(
        question: String,
        drafts: [CandidateDraft],
        persona: String,
        synthesizer: HybridCandidate,
        config: ChatConfig
    ) -> GenerationRequest {
        GenerationRequest(
            modelID: synthesizer.modelID,
            messages: [
                ChatMessagePayload(role: .system, text: systemText(persona: persona)),
                ChatMessagePayload(role: .user, text: userText(question: question, drafts: drafts)),
            ],
            config: config
        )
    }
}