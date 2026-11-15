import Foundation

/// Deterministic stand-in used by Milestone 1 and by the unit tests, so the whole
/// UI, tree, cancellation, and metrics path can be exercised before any real engine
/// or socket exists. It emits real `.thinking` chunks on purpose: the reasoning panel
/// must be proven to appear only for providers that actually produce thinking.
public struct MockStreamingProvider: InferenceProvider {
    public let id: String
    public var displayName: String { "Mock Engine (on-device)" }
    public var networkClass: NetworkClass { .onDevice }

    /// Mocks emit thinking, so the capability flag must say so.
    public var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            streaming: true,
            thinking: thinkingCapable,
            toolCalling: false,
            vision: false,
            modelListing: true,
            contextLengthAdjustable: true
        )
    }

    public var thinkingCapable: Bool
    public var tokenDelayNanoseconds: UInt64
    public var failAfterTokens: Int?

    public init(
        id: String = "mock",
        thinkingCapable: Bool = true,
        tokenDelayNanoseconds: UInt64 = 20_000_000,
        failAfterTokens: Int? = nil
    ) {
        self.id = id
        self.thinkingCapable = thinkingCapable
        self.tokenDelayNanoseconds = tokenDelayNanoseconds
        self.failAfterTokens = failAfterTokens
    }

    public static let instant = MockStreamingProvider(tokenDelayNanoseconds: 0)

    public func models() async throws -> [ModelInfo] {
        [
            ModelInfo(
                id: "cairn-mock-8b",
                displayName: "Cairn Mock 8B",
                providerID: id,
                parameterSize: "8B",
                quantization: "Q4_K_M",
                contextLength: 8192,
                supportsVision: false,
                supportsThinking: thinkingCapable
            ),
            ModelInfo(
                id: "cairn-mock-3b",
                displayName: "Cairn Mock 3B",
                providerID: id,
                parameterSize: "3B",
                quantization: "Q4_K_S",
                contextLength: 4096
            ),
        ]
    }

    public func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
        let delay = tokenDelayNanoseconds
        let emitThinking = thinkingCapable && request.params.thinkingEnabled
        let failureAt = failAfterTokens
        let promptChars = request.promptCharacterCount

        return AsyncThrowingStream { continuation in
            let work = Task {
                let started = Date()
                var produced = 0
                var firstTokenAt: Date?
                do {
                    if emitThinking {
                        for fragment in Self.thinkingFragments {
                            try await Self.tick(delay)
                            continuation.yield(.thinking(fragment))
                        }
                    }
                    for fragment in Self.contentFragments(for: request) {
                        try await Self.tick(delay)
                        produced += 1
                        if firstTokenAt == nil { firstTokenAt = Date() }
                        continuation.yield(.content(fragment))
                        if let failureAt, produced >= failureAt {
                            throw MockProviderError.simulatedMidStream
                        }
                    }
                    let elapsed = Date().timeIntervalSince(started)
                    let ttfb = firstTokenAt?.timeIntervalSince(started)
                    continuation.yield(
                        .metrics(
                            GenerationMetrics(
                                tokensGenerated: produced,
                                promptTokens: promptChars / 4,
                                elapsedSeconds: elapsed,
                                timeToFirstTokenSeconds: ttfb,
                                finishReason: .stop
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func tick(_ nanoseconds: UInt64) async throws {
        if nanoseconds > 0 { try await Task.sleep(nanoseconds: nanoseconds) }
        try Task.checkCancellation()
    }

    static let thinkingFragments = [
        "Restating the ask. ",
        "Checking what is known locally. ",
        "Drafting a short, direct answer.",
    ]

    static func contentFragments(for request: GenerationRequest) -> [String] {
        let lastUser = request.messages.last(where: { $0.role == .user })?.text ?? ""
        let trimmed = lastUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = trimmed.isEmpty ? "your question" : trimmed
        return [
            "Mock answer to: ",
            subject,
            ". ",
            "This is streamed token by token from a deterministic mock, ",
            "so the tree, cancellation, and metrics paths can be verified ",
            "before any real inference engine is wired up.",
        ]
    }

    public enum MockProviderError: Error, Equatable, LocalizedError {
        case simulatedMidStream

        public var errorDescription: String? {
            "The mock engine was configured to fail part-way through this turn."
        }
    }
}



