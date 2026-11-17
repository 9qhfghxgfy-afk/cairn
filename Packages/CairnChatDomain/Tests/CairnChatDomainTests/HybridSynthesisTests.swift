import XCTest
@testable import CairnChatDomain

/// The synthesis stage: one unified answer, honestly attributed, given only the question and the
/// drafts, and never allowed to invent reasoning a candidate never showed.
final class HybridSynthesisTests: XCTestCase {

    private func writerJob(
        _ provider: ScriptedProvider,
        engineID: String = "writer",
        question: String = "What is a cairn?"
    ) -> HybridSynthesisJob {
        HybridSynthesisJob(
            candidate: HybridCandidate(engineID: engineID, modelID: "writer-model"),
            provider: provider,
            networkClass: provider.networkClass,
            question: question,
            persona: "",
            config: ChatConfig()
        )
    }

    private func pair() -> (sideA: ScriptedProvider, sideB: ScriptedProvider) {
        (
            ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["stone ", "cairn "]),
            ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["a pile of stone"])
        )
    }

    func testTheUnifiedAnswerIsWrittenAndAttributedToTheEngineThatWroteIt() async throws {
        let writer = ScriptedProvider(id: "writer", name: "Writer", networkClass: .privateLan, fragments: ["Both say: ", "a cairn."])
        let sides = pair()
        let job = HybridTestSupport.job(
            mode: .hybridSynthesized,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [sides.sideA, sides.sideB, writer],
            classes: [.privateLan, .publicInternet],
            synthesis: writerJob(writer)
        )

        let events = try await HybridTestSupport.drain(job)
        let result = try HybridTestSupport.outcome(of: events)

        XCTAssertEqual(result.synthesis?.text, "Both say: a cairn.")
        XCTAssertEqual(result.primaryText, "Both say: a cairn.", "a synthesized turn stores the unified answer")
        XCTAssertEqual(result.state, .complete)
        XCTAssertEqual(result.provenance.synthesizerEngineID, "writer")
        XCTAssertTrue(result.provenance.synthesisRan)
        XCTAssertTrue(events.contains { if case .synthesisStarted = $0 { return true }; return false })
        XCTAssertTrue(result.provenance.summary.contains("Synthesized by writer"))
    }

    func testTheWriterReceivesTheQuestionAndTheDraftsAndNoHistory() async throws {
        let ledger = HybridLedger()
        let sideA = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["the left side says yes"])
        let sideB = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["the right side says no"])
        let writer = ScriptedProvider(id: "writer", name: "Writer", networkClass: .privateLan, fragments: ["written"], ledger: ledger)
        let job = HybridTestSupport.job(
            mode: .hybridSynthesized,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [sideA, sideB, writer],
            classes: [.privateLan, .publicInternet],
            synthesis: writerJob(writer, question: "How do I stack a cairn?")
        )

        _ = try await HybridTestSupport.drain(job)
        let captured = await ledger.request(for: "writer")
        let request = try XCTUnwrap(captured)

        XCTAssertEqual(request.messages.count, 2, "instruction plus question-and-drafts, never a transcript")
        XCTAssertEqual(request.messages.first?.role, .system)
        XCTAssertTrue(request.messages[0].text.contains("Agreements"))
        let payload = request.messages[1].text
        XCTAssertTrue(payload.contains("How do I stack a cairn?"))
        XCTAssertTrue(payload.contains("the left side says yes"))
        XCTAssertTrue(payload.contains("the right side says no"))
    }

    func testAFailedWriterKeepsTheDraftsAndSaysWhatWasLost() async throws {
        let sideA = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["a usable ", "answer"])
        let sideB = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["another answer"])
        let writer = ScriptedProvider(id: "writer", name: "Writer", networkClass: .privateLan, fragments: ["half-written "], failureMessage: "The writer ran out of context.")
        let job = HybridTestSupport.job(
            mode: .hybridSynthesized,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [sideA, sideB, writer],
            classes: [.privateLan, .publicInternet],
            synthesis: writerJob(writer)
        )

        let events = try await HybridTestSupport.drain(job)
        let result = try HybridTestSupport.outcome(of: events)

        XCTAssertEqual(result.synthesis?.failure, "The writer ran out of context.")
        XCTAssertEqual(result.primaryText, "half-written", "the writer's own unfinished text stands, attributed to the writer")
        XCTAssertEqual(result.state, .interrupted, "an unfinished unified answer must not be stored as finished")
        XCTAssertEqual(result.provenance.synthesisFailure, "The writer ran out of context.")
        XCTAssertEqual(result.drafts.first(where: { $0.order == 0 })?.text, "a usable answer", "the drafts stay attached, so nothing is lost")
    }

    func testAWriterThatSaidNothingFallsBackToASideThatAnswered() async throws {
        let sideA = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["a usable ", "answer"])
        let sideB = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["another answer"])
        let writer = ScriptedProvider(id: "writer", name: "Writer", networkClass: .privateLan, fragments: [], failureMessage: "The writer never started.")
        let job = HybridTestSupport.job(
            mode: .hybridSynthesized,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [sideA, sideB, writer],
            classes: [.privateLan, .publicInternet],
            synthesis: writerJob(writer)
        )

        let events = try await HybridTestSupport.drain(job)
        let result = try HybridTestSupport.outcome(of: events)

        XCTAssertEqual(result.primaryText, "a usable answer", "with nothing unified to show, a real answer still stands")
        XCTAssertEqual(result.state, .complete)
        XCTAssertEqual(result.provenance.synthesisFailure, "The writer never started.")
    }

    func testNoReasoningIsInventedForTheUnifiedAnswer() async throws {
        let sideA = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["answer a"], thinkingFragments: ["thinking about a"])
        let sideB = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["answer b"])
        let writer = ScriptedProvider(id: "writer", name: "Writer", networkClass: .privateLan, fragments: ["a unified answer"])
        let job = HybridTestSupport.job(
            mode: .hybridSynthesized,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [sideA, sideB, writer],
            classes: [.privateLan, .publicInternet],
            synthesis: writerJob(writer)
        )

        let events = try await HybridTestSupport.drain(job)
        let result = try HybridTestSupport.outcome(of: events)

        XCTAssertNotNil(result.drafts[0].thinking, "a side that emitted reasoning keeps it")
        XCTAssertNil(result.synthesis?.thinking, "a writer that emitted none must not be shown one")
    }

    func testTheLiveSnapshotFollowsTheTurnFromQueuedToFinished() async throws {
        let sides = pair()
        let job = HybridTestSupport.job(
            mode: .hybridParallel,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [sides.sideA, sides.sideB],
            classes: [.privateLan, .publicInternet]
        )
        var snapshot = HybridSnapshot.starting(candidates: job.candidates, labels: job.labels)
        XCTAssertEqual(snapshot.progress.map(\.phase), [.queued, .queued])

        for try await event in HybridEngine.stream(job) { snapshot.apply(event) }

        XCTAssertEqual(snapshot.stage, .finished)
        XCTAssertEqual(snapshot.progress.map(\.phase), [.completed, .completed])
        XCTAssertEqual(snapshot.progress.map(\.sourceLabel), ["LAN server", "Cloud server"])
        XCTAssertFalse(snapshot.anyRunning)
    }

    /// Cancellation is driven by progress, not by a clock. A fixed sleep before the stop is what
    /// went red on a loaded CI runner (`44193788309`): no wall-clock guarantee exists there. The
    /// stop is issued only once the drain has actually watched a side say something, and the drain
    /// checks its own cancellation between events exactly as the session drain does.
    func testStoppingTheTurnEndsTheStreamWithoutClaimingSuccess() async throws {
        let slowA = ScriptedProvider(id: "lan", name: "LAN server", networkClass: .privateLan, fragments: ["one ", "two ", "three ", "four "], tokenDelay: 20_000_000)
        let slowB = ScriptedProvider(id: "cloud", name: "Cloud server", networkClass: .publicInternet, fragments: ["five ", "six ", "seven ", "eight "], tokenDelay: 20_000_000)
        let job = HybridTestSupport.job(
            mode: .hybridParallel,
            pairs: [("lan", "server-a"), ("cloud", "cloud-a")],
            providers: [slowA, slowB],
            classes: [.privateLan, .publicInternet]
        )

        let flagged = PartialAnswerFlag()
        let drain = Task {
            var seen: [HybridEvent] = []
            do {
                for try await event in HybridEngine.stream(job) {
                    seen.append(event)
                    if case .draftUpdated(let draft) = event, !draft.text.isEmpty {
                        await flagged.raise()
                    }
                    try Task.checkCancellation()
                }
            } catch {}
            return seen
        }

        let raised = await flagged.waitUntilRaised()
        drain.cancel()
        let events = await drain.value

        XCTAssertTrue(raised, "a side must answer before the stop can be issued")
        XCTAssertTrue(
            events.contains { if case .draftUpdated(let draft) = $0 { return !draft.text.isEmpty }; return false },
            "partial answers should reach the node before the stop lands"
        )
        if let result = try? HybridTestSupport.outcome(of: events) {
            XCTAssertNotEqual(result.state, .complete, "a stopped turn may not be stored as finished")
        }
    }
}