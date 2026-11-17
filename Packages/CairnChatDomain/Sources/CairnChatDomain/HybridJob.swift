import Foundation

/// One hybrid turn, fully resolved: which engines, which models, which request each side gets,
/// and who answers the memory question.
///
/// Everything here is a value the engine can run without a session, a store, or a view — which
/// is what makes the task-group behaviour testable with two mock providers.
public struct HybridJob: Sendable {
    public var mode: InferenceMode
    public var plan: HybridPlan
    /// One request per candidate, at the same index. Each side gets the conversation assembled
    /// for **its own** engine, so a server's capability filter applies to its own request.
    public var requests: [GenerationRequest]
    public var providers: [String: any InferenceProvider]
    /// Parallel to `plan.candidates` — the schedule is built from this, never from a name.
    public var networkClasses: [NetworkClass]
    /// `nil` for Parallel mode: compare the drafts, write no unified answer.
    public var synthesis: HybridSynthesisJob?
    public var residency: any HybridResidencyGating

    public init(
        mode: InferenceMode,
        plan: HybridPlan,
        requests: [GenerationRequest],
        providers: [String: any InferenceProvider],
        networkClasses: [NetworkClass],
        synthesis: HybridSynthesisJob? = nil,
        residency: any HybridResidencyGating = NeverTwoOnDeviceResident()
    ) {
        self.mode = mode
        self.plan = plan
        self.requests = requests
        self.providers = providers
        self.networkClasses = networkClasses
        self.synthesis = synthesis
        self.residency = residency
    }

    public var candidates: [HybridCandidate] { plan.candidates }

    public func provider(for candidate: HybridCandidate) -> (any InferenceProvider)? {
        providers[candidate.engineID]
    }

    public func request(at index: Int) -> GenerationRequest? {
        requests.indices.contains(index) ? requests[index] : nil
    }

    /// Engine id to the engine's own name, so a draft is attributed by what produced it.
    public var labels: [String: String] {
        providers.reduce(into: [String: String]()) { partial, entry in
            partial[entry.key] = entry.value.displayName
        }
    }

    /// The first reason this turn cannot run, in words. Better than a stop button that does
    /// nothing: an on-device model that is not installed is a fact the user should be told.
    public var blockingReason: String? {
        if let issue = plan.issue { return issue.reasonText }
        for candidate in candidates where provider(for: candidate) == nil {
            return "The engine \(candidate.engineID) is not registered right now."
        }
        return nil
    }
}