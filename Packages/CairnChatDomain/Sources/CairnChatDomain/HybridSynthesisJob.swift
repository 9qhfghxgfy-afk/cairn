import Foundation

/// The synthesizer stage of a hybrid turn, resolved and ready to run.
///
/// It carries what the prompt needs rather than a finished request, because the drafts it must
/// read do not exist until the candidates have answered. The session resolves the engine, the
/// question, and the chat's persona; the engine renders the prompt when the drafts land.
public struct HybridSynthesisJob: Sendable {
    public var candidate: HybridCandidate
    public var provider: any InferenceProvider
    public var networkClass: NetworkClass
    /// The turn being answered — the only conversation content this stage receives.
    public var question: String
    public var persona: String
    public var config: ChatConfig

    public init(
        candidate: HybridCandidate,
        provider: any InferenceProvider,
        networkClass: NetworkClass,
        question: String,
        persona: String,
        config: ChatConfig
    ) {
        self.candidate = candidate
        self.provider = provider
        self.networkClass = networkClass
        self.question = question
        self.persona = persona
        self.config = config
    }

    public var isOnDevice: Bool { networkClass == .onDevice }

    /// Exactly the question plus the drafts, and nothing else from the conversation.
    public func request(reading drafts: [CandidateDraft]) -> GenerationRequest {
        HybridSynthesisPrompt.request(
            question: question,
            drafts: drafts,
            persona: persona,
            synthesizer: candidate,
            config: config
        )
    }
}