import Foundation

/// How one hybrid turn was produced, stored on the single node it wrote.
///
/// This is provenance, not telemetry: nothing here leaves the device, and it exists so a
/// synthesized answer can be read back later and said out loud — which engines were asked,
/// which one wrote the unified answer, and how many of the drafts failed. No address, no
/// credential, no prompt text.
public struct HybridProvenance: Sendable, Equatable, Codable {
    public var mode: InferenceMode
    /// The engine that wrote the unified answer. `nil` in Parallel mode, where there is no
    /// synthesizer, and when no synthesizer could be resolved.
    public var synthesizerEngineID: String?
    public var synthesizerModelID: String?
    public var candidateCount: Int
    /// Drafts that ended failed. Named so a reader knows the unified answer was built from
    /// fewer sources than it looks.
    public var failedCandidateCount: Int
    public var synthesisRan: Bool
    /// The synthesizer's own failure, kept beside the answer it could not write.
    public var synthesisFailure: String?

    public init(
        mode: InferenceMode,
        synthesizerEngineID: String? = nil,
        synthesizerModelID: String? = nil,
        candidateCount: Int = 0,
        failedCandidateCount: Int = 0,
        synthesisRan: Bool = false,
        synthesisFailure: String? = nil
    ) {
        self.mode = mode
        self.synthesizerEngineID = synthesizerEngineID
        self.synthesizerModelID = synthesizerModelID
        self.candidateCount = candidateCount
        self.failedCandidateCount = failedCandidateCount
        self.synthesisRan = synthesisRan
        self.synthesisFailure = synthesisFailure
    }

    /// One line for the message bubble: what produced this answer, in plain words.
    public var summary: String {
        let drafts = candidateCount == 1 ? "1 draft" : "\(candidateCount) drafts"
        if mode == .hybridParallel {
            return failedCandidateCount > 0
                ? "Compared \(drafts) · \(failedCandidateCount) failed"
                : "Compared \(drafts)"
        }
        let writer = [synthesizerEngineID, synthesizerModelID]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let base = writer.isEmpty ? "Synthesized from \(drafts)" : "Synthesized by \(writer) from \(drafts)"
        return failedCandidateCount > 0
            ? "\(base) · \(failedCandidateCount) failed"
            : base
    }
}