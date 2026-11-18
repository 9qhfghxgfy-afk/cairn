import Foundation

/// Reading documents the user attached, on this device, and choosing the passages that answer the
/// question being asked.
///
/// The whole of retrieval runs here and on the phone: nothing in this file can reach a network, a
/// model, or an embedding service. What goes onward to a server is the question, the persona, the
/// conversation, and these numbered passages — which is a decision the user made by attaching a file
/// and pressing send, and which the injected block states out loud so the model cannot answer from
/// memory and pass it off as the document.
public enum Grounding {

    /// Every document attachment on the visible path, chunked.
    ///
    /// The corpus is the **path**, not the whole tree: a passage from a branch the user is not looking
    /// at must not quietly steer this answer. A document attached two turns ago is still in the corpus,
    /// which is what makes "what did the file I sent earlier say about X?" answerable.
    public static func corpus(from path: [ChatNode]) -> DocumentCorpus {
        var chunks: [DocumentChunk] = []
        var seen: Set<UUID> = []
        for node in path where node.role == .user {
            for attachment in Attachments.sorted(node.attachments) {
                guard attachment.kind == .document, attachment.hasText,
                      !seen.contains(attachment.id) else { continue }
                seen.insert(attachment.id)
                chunks.append(contentsOf: DocumentChunker.chunks(
                    attachment.text ?? "",
                    documentID: attachment.id,
                    documentName: attachment.name
                ))
            }
        }
        return DocumentCorpus(chunks: chunks)
    }

    /// The passages for one question, in rank order and inside the budget, numbered from one.
    public static func ground(
        question: String,
        corpus: DocumentCorpus,
        budget: GroundingBudget = .standard
    ) -> GroundingOutcome {
        let considered = corpus.documentCount
        guard !corpus.isEmpty else {
            return GroundingOutcome(documentsConsidered: considered)
        }
        let ranked = LexicalIndex(chunks: corpus.chunks).rank(
            question, count: max(budget.passageCount * 3, budget.passageCount)
        )
        guard !ranked.isEmpty else {
            return GroundingOutcome(documentsConsidered: considered)
        }

        var chosen: [ScoredChunk] = []
        var used = 0
        var dropped = 0
        for scored in ranked {
            if chosen.count >= budget.passageCount { dropped += 1; continue }
            let cost = scored.chunk.text.count
            guard used + cost <= budget.characterCount else {
                dropped += 1
                continue
            }
            used += cost
            chosen.append(scored)
        }
        // The score travels with the chunk it scored, so the citation an answer is credited with says not
        // only where the passage came from but how strongly it matched — the one fact about the retrieval a
        // reader can use to decide whether to go and read the file themselves.
        let passages = chosen.enumerated().map { offset, scored in
            RetrievedPassage(
                number: offset + 1,
                documentID: scored.chunk.documentID,
                documentName: scored.chunk.documentName,
                chunkIndex: scored.chunk.index,
                startCharacter: scored.chunk.startCharacter,
                text: scored.chunk.text,
                score: scored.score
            )
        }
        return GroundingOutcome(
            passages: passages,
            citations: passages.map(SourceCitation.init),
            documentsConsidered: considered,
            passagesDroppedForBudget: dropped
        )
    }

    /// The convenience path the session uses: corpus and question from the same path of nodes.
    public static func ground(
        question: String, path: [ChatNode], budget: GroundingBudget = .standard
    ) -> GroundingOutcome {
        ground(question: question, corpus: corpus(from: path), budget: budget)
    }

    /// The question a turn is being grounded on: the newest user message on the path. A tool result is
    /// never a node — it lives inside the answer's `ToolRun` — so every user node here is something the
    /// user actually typed.
    public static func question(in path: [ChatNode]) -> String {
        path.last { $0.role == .user }?.text ?? ""
    }

    /// A turn's grounding, decided once and reused by the prompt, the preview and the node's citations
    /// — so the three of them cannot disagree about what was searched.
    public static func outcome(for path: [ChatNode], windowTokens: Int?) -> GroundingOutcome {
        ground(
            question: question(in: path),
            corpus: corpus(from: path),
            budget: GroundingBudget.fitted(toContextWindow: windowTokens)
        )
    }
}
