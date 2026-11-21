import Foundation
import Testing
@testable import CairnInferenceNative

/// Who is allowed to hand memory back, and when.
///
/// These run on a host with no Metal and no MLX, which is exactly where this rule can be proved: the
/// ledger is a counter with two callbacks, and the callbacks are what a device build fills in. What is
/// pinned is the one tension that matters — pressure and backgrounding both want the model gone now, and
/// a generation in flight needs its weights to stay until it finishes.
struct MLXTurnLedgerTests {
    @Test func aReleaseAskedForMidTurnWaitsForTheEndOfThatTurn() async {
        let calls = CallLog()
        let ledger = MLXTurnLedger(
            onFlush: { await calls.note("flush") },
            onRelease: { await calls.note("release") }
        )
        await ledger.beginTurn()
        await ledger.requestRelease()

        #expect(await ledger.releaseIsPending)
        #expect(await calls.all.isEmpty)

        await ledger.endTurn()
        // Release first, then the pool: the jetsam report that motivated all of this counted the weights
        // and the dirty buffers beside them, and a release gives both back.
        #expect(await calls.all == ["release", "flush"])
        #expect(await ledger.turnsInFlight == 0)
        #expect(await ledger.releaseIsPending == false)
    }

    @Test func twoOverlappingTurnsHoldTheReleaseUntilTheLastOneEnds() async {
        // A stop that is still unwinding while the next turn starts is a real shape in this app, and a
        // flag would let the first ending release a model the second was still using.
        let calls = CallLog()
        let ledger = MLXTurnLedger(
            onFlush: { await calls.note("flush") },
            onRelease: { await calls.note("release") }
        )
        await ledger.beginTurn()
        await ledger.beginTurn()
        await ledger.requestRelease()

        await ledger.endTurn()
        #expect(await calls.all.isEmpty)
        #expect(await ledger.turnsInFlight == 1)

        await ledger.endTurn()
        #expect(await calls.all == ["release", "flush"])
        #expect(await ledger.turnsInFlight == 0)
    }

    @Test func anIdleTurnEndStillHandsTheBuffersBack() async {
        // Nothing asked for the model to go, so the container stays. The pool goes back regardless,
        // because a buffer pool held between turns is dirty memory the phone is paying for.
        let calls = CallLog()
        let ledger = MLXTurnLedger(
            onFlush: { await calls.note("flush") },
            onRelease: { await calls.note("release") }
        )
        await ledger.beginTurn()
        await ledger.endTurn()
        #expect(await calls.all == ["flush"])
    }

    @Test func aFlushUnderARunningTurnDoesNotPullBuffersOutFromUnderIt() async {
        let calls = CallLog()
        let ledger = MLXTurnLedger(onFlush: { await calls.note("flush") })
        await ledger.beginTurn()
        await ledger.requestFlush()
        #expect(await calls.all.isEmpty)

        await ledger.endTurn()
        #expect(await calls.all == ["flush"])
    }

    @Test func anUnpairedEndNeverDragsTheCountNegative() async {
        // An end with no turn behind it is a bug somewhere else, and it must not be allowed to leave the
        // counter lying about the next turn.
        let calls = CallLog()
        let ledger = MLXTurnLedger(onFlush: { await calls.note("flush") })
        await ledger.endTurn()
        #expect(await ledger.turnsInFlight == 0)

        await ledger.beginTurn()
        await ledger.endTurn()
        #expect(await calls.all == ["flush"])
    }

    @Test func aReleaseWithNothingRunningIsTakenImmediately() async {
        // Backgrounding an idle app is the common case, and a deferred release there would be a release
        // that never happens, because no turn is coming to collect it.
        let calls = CallLog()
        let ledger = MLXTurnLedger(
            onFlush: { await calls.note("flush") },
            onRelease: { await calls.note("release") }
        )
        await ledger.requestRelease()
        #expect(await calls.all == ["release", "flush"])
        #expect(await ledger.releaseIsPending == false)
    }
}

/// Calls the ledger's callbacks in order, so "which ran, and when" is an assertion rather than a hope.
actor CallLog {
    private var notes: [String] = []

    func note(_ note: String) { notes.append(note) }

    var all: [String] { notes }
}
