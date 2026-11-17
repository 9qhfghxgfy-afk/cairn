import Foundation
@testable import CairnChatDomain

/// Records when each side of a hybrid turn is actually in flight, so "these two ran together" and
/// "never two on-device models at once" are measurements a test reads rather than intentions it
/// trusts. `peakLiveOnDevice` is the memory rule made observable.
actor HybridLedger {
    private var live = 0
    private var liveOnDevice = 0
    private(set) var peakLive = 0
    private(set) var peakLiveOnDevice = 0
    private(set) var evictions = 0
    private var requests: [String: GenerationRequest] = [:]

    func began(engineID: String, onDevice: Bool, request: GenerationRequest) {
        live += 1
        requests[engineID] = request
        if onDevice { liveOnDevice += 1 }
        peakLive = max(peakLive, live)
        peakLiveOnDevice = max(peakLiveOnDevice, liveOnDevice)
    }

    func ended(onDevice: Bool) {
        live -= 1
        if onDevice { liveOnDevice -= 1 }
    }

    func evicted() { evictions += 1 }

    func request(for engineID: String) -> GenerationRequest? { requests[engineID] }

    /// One read of everything a test asserts, so the assertions themselves stay synchronous —
    /// `XCTAssertEqual` takes an autoclosure, which cannot await.
    func snapshot() -> HybridLedgerReading {
        HybridLedgerReading(peakLive: peakLive, peakLiveOnDevice: peakLiveOnDevice, evictions: evictions)
    }

    /// Blocks until `count` sides are in flight at once. A serialized run never reaches the count
    /// and returns false at the timeout, which is what makes overlap a proof and not a hope.
    func waitFor(concurrencyAtLeast count: Int, timeout: Duration = .milliseconds(600)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while live < count {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return true
    }
}

/// The residency answer a test chooses, counting every release so "sequentially with a clean
/// release between them" can be asserted rather than assumed.
struct SpyResidencyGate: HybridResidencyGating {
    let ledger: HybridLedger
    let allowsTwo: Bool

    init(ledger: HybridLedger, allowsTwo: Bool = false) {
        self.ledger = ledger
        self.allowsTwo = allowsTwo
    }

    func allowsTwoOnDeviceModelsResident() -> Bool { allowsTwo }

    @MainActor func evictResidentModel() async { await ledger.evicted() }
}

/// A failure a test names. It is a `LocalizedError` on purpose: the engine stores
/// `localizedDescription` as a draft's failure, and a test has to be able to assert the reason a
/// user would actually read.
struct HybridTestError: Error, Equatable, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// The ledger's counters, read in one awaitable step.
struct HybridLedgerReading: Sendable, Equatable {
    var peakLive: Int
    var peakLiveOnDevice: Int
    var evictions: Int
}

/// A provider that says exactly what the test wrote, marks the ledger on the way in and out, and
/// can fail part-way. `overlapTarget` holds it still until the promised number of sides are in
/// flight, so a concurrent group has to prove it overlapped.
struct ScriptedProvider: InferenceProvider {
    let id: String
    var name: String
    var networkClass: NetworkClass
    var fragments: [String] = ["alpha ", "beta ", "gamma"]
    var thinkingFragments: [String] = []
    var tokenDelay: UInt64 = 0
    var failureMessage: String?
    var overlapTarget: Int = 0
    var ledger: HybridLedger?
    var modelID: String = "test-model"

    var displayName: String { name }
    var capabilities: ProviderCapabilities { ProviderCapabilities(thinking: !thinkingFragments.isEmpty) }
    var serverProfileID: UUID? { nil }

    func models() async throws -> [ModelInfo] {
        [ModelInfo(id: modelID, displayName: modelID, providerID: id)]
    }

    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<StreamChunk, any Error> {
        let ledger = ledger
        let onDevice = networkClass == .onDevice
        let pieces = fragments
        let thinking = thinkingFragments
        let delay = tokenDelay
        let failure = failureMessage
        let engineID = id
        let overlap = overlapTarget

        return AsyncThrowingStream { continuation in
            let work = Task {
                await ledger?.began(engineID: engineID, onDevice: onDevice, request: request)
                if overlap > 1 { _ = await ledger?.waitFor(concurrencyAtLeast: overlap) }
                do {
                    for fragment in thinking {
                        try await Self.tick(delay)
                        continuation.yield(.thinking(fragment))
                    }
                    for fragment in pieces {
                        try await Self.tick(delay)
                        continuation.yield(.content(fragment))
                    }
                    if let failure { throw HybridTestError(message: failure) }
                    continuation.yield(
                        .metrics(
                            GenerationMetrics(
                                tokensGenerated: pieces.count,
                                promptTokens: request.promptCharacterCount / 4,
                                elapsedSeconds: 0.02,
                                timeToFirstTokenSeconds: 0.005,
                                finishReason: .stop
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await ledger?.ended(onDevice: onDevice)
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func tick(_ nanoseconds: UInt64) async throws {
        if nanoseconds > 0 { try await Task.sleep(nanoseconds: nanoseconds) }
        try Task.checkCancellation()
    }
}

/// Shared fixtures for the engine tests: a job is mostly plumbing, and every test would repeat
/// the same parallel arrays of candidates, classes, and requests without it.
enum HybridTestSupport {

    static func plan(_ pairs: [(String, String)]) -> HybridPlan {
        HybridPlan(candidates: pairs.map { HybridCandidate(engineID: $0.0, modelID: $0.1) })
    }

    static func request(modelID: String, question: String = "What is a cairn?") -> GenerationRequest {
        GenerationRequest(
            modelID: modelID,
            messages: [ChatMessagePayload(role: .user, text: question)],
            config: ChatConfig()
        )
    }

    static func job(
        mode: InferenceMode,
        pairs: [(String, String)],
        providers: [any InferenceProvider],
        classes: [NetworkClass],
        residency: any HybridResidencyGating = NeverTwoOnDeviceResident(),
        synthesis: HybridSynthesisJob? = nil
    ) -> HybridJob {
        let plan = plan(pairs)
        return HybridJob(
            mode: mode,
            plan: plan,
            requests: pairs.map { request(modelID: $0.1) },
            providers: Dictionary(
                providers.map { ($0.id, $0) },
                uniquingKeysWith: { _, last in last }
            ),
            networkClasses: classes,
            synthesis: synthesis,
            residency: residency
        )
    }

    static func drain(_ job: HybridJob) async throws -> [HybridEvent] {
        var events: [HybridEvent] = []
        for try await event in HybridEngine.stream(job) { events.append(event) }
        return events
    }

    static func outcome(of events: [HybridEvent]) throws -> HybridTurnOutcome {
        for event in events.reversed() {
            if case .outcome(let result) = event { return result }
        }
        throw HybridTestError(message: "the turn ended without an outcome event")
    }
}