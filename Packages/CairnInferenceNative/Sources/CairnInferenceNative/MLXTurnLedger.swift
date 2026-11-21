import Foundation

/// Counts the generations that are running, so "give memory back" never means "kill the answer the
/// person is watching".
///
/// Two things pull against each other and this type is where the pull is settled. Memory pressure and
/// backgrounding both want the model gone **now**; a generation in flight needs its weights and its
/// buffers to stay until it finishes, because an unload mid-stream produces a torn turn and frees
/// nothing the runtime was not going to free anyway. So a release request is honoured immediately when
/// nothing is running and recorded when something is, and it lands at the end of that turn — one turn
/// later, which is also the moment the person has their answer.
///
/// A **count** and not a flag, because more than one stream can genuinely overlap in this app: a stop
/// that is still unwinding while the next turn starts, or a tool loop whose second request goes out
/// before the first has finished closing. A flag would let the first of those endings release a model
/// the second was still using.
///
/// This type holds no MLX type and no model, which is what makes the whole deferral rule provable on
/// a host with no Metal — it is a counter with two callbacks, and the callbacks are what a device build
/// fills in.
public actor MLXTurnLedger {
    private var turns = 0
    private var pendingRelease = false
    private let onFlush: @Sendable () async -> Void
    private let onRelease: @Sendable () async -> Void

    /// - Parameters:
    ///   - onFlush: hand the runtime's buffer pool back to the system. Called when a turn ends and
    ///     nothing asked for the model to go.
    ///   - onRelease: drop the resident container. Called when a release was asked for and nothing is
    ///     running any more — or immediately, if nothing was running when it was asked for.
    public init(
        onFlush: @escaping @Sendable () async -> Void = {},
        onRelease: @escaping @Sendable () async -> Void = {}
    ) {
        self.onFlush = onFlush
        self.onRelease = onRelease
    }

    public var turnsInFlight: Int { turns }

    /// A release was asked for and is waiting on a turn.
    public var releaseIsPending: Bool { pendingRelease }

    public func beginTurn() {
        turns += 1
    }

    /// A turn finished. If a release piled up behind it, that release runs now; otherwise the buffers
    /// still go back, because a pool held between turns is dirty memory the phone is paying for.
    /// A turn finished. The pool goes back only once the last turn in flight has ended — flushing under
    /// a turn that is still generating takes the buffers out from under it. If a release piled up behind
    /// these turns, that release lands on the same condition, which is the whole deferral rule.
    public func endTurn() async {
        guard turns > 0 else { return }
        turns -= 1
        guard turns == 0 else { return }
        if pendingRelease {
            await releaseNow()
        } else {
            await onFlush()
        }
    }

    /// Backgrounding, critical pressure, or a user asking for the model gone. Immediate when the
    /// ledger is idle, deferred to the last `endTurn()` when it is not.
    public func requestRelease() async {
        guard turns > 0 else {
            await releaseNow()
            return
        }
        pendingRelease = true
    }

    /// Give buffers back if — and only if — nothing is generating. A flush under a running turn takes
    /// the buffers out from under it.
    public func requestFlush() async {
        guard turns == 0 else { return }
        await onFlush()
    }

    private func releaseNow() async {
        pendingRelease = false
        await onRelease()
        // Releasing the weights is worth the most when the pool beside them goes back too; the jetsam
        // report that motivated all of this counted both.
        await onFlush()
    }
}
