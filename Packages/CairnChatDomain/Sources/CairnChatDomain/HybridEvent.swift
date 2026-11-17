import Foundation

/// What happened in one hybrid turn, in one vocabulary the session can drain.
///
/// Errors are values inside `draftUpdated` / `outcome`, never thrown away the turn: a candidate
/// that fails has to keep its partial text and say why, while the surviving candidates still
/// answer. Only a cancelled turn terminates early.
public enum HybridEvent: Sendable, Equatable {
    /// Live status of one candidate — the Parallel panels read nothing else.
    case candidateProgress(CandidateProgress)
    /// A candidate draft, rewritten with whatever has landed so far.
    case draftUpdated(CandidateDraft)
    /// The candidates are in; the synthesizer started.
    case synthesisStarted
    /// One chunk of the synthesized answer, passed through untouched.
    case synthesisChunk(StreamChunk)
    /// The turn's final state: drafts, synthesis, provenance, and the text to store.
    case outcome(HybridTurnOutcome)
}