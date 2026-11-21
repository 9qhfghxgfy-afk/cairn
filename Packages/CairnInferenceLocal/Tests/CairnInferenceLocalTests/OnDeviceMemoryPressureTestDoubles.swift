import Foundation
@testable import CairnInferenceLocal

/// Release calls the registry made, recorded by id.
///
/// Ids only — the same rule production follows: typed metadata out of a memory path, never model
/// content. `@unchecked Sendable` because its only state is the recorded list, guarded by the lock, and
/// `NSLock.lock()` cannot be called from an async function, which is what the registry's unloader is.
final class ReleaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []

    func record(_ id: String) {
        lock.lock(); ids.append(id); lock.unlock()
    }

    var recorded: [String] {
        lock.lock(); defer { lock.unlock() }; return ids
    }
}

/// How many times buffers were handed back. A count rather than a flag, because "flushed once" and
/// "flushed every time a warning arrived" are different claims and only one of them is a bug.
final class FlushCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = 0

    func add() {
        lock.lock(); seen += 1; lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }; return seen
    }
}

/// A memory-pressure source the test drives by hand.
///
/// This is why the watch takes sources as a parameter instead of reaching for UIKit: the release path a
/// jetsam event takes has to be provable on a machine that cannot produce a jetsam event, and a source
/// that could only be the system's own would make the whole rule untestable off a phone.
actor ScriptedPressureSource: MemoryPressureObserving {
    private var continuation: AsyncStream<MemoryPressureLevel>.Continuation?
    private(set) var didStop = false

    func memoryPressureSignals() -> AsyncStream<MemoryPressureLevel> {
        let (stream, continuation) = AsyncStream<MemoryPressureLevel>.makeStream()
        self.continuation = continuation
        return stream
    }

    /// Sends a level, waiting for the watcher to have subscribed first.
    ///
    /// The watch starts on its own task, so an emit that raced it would drop the event and the test
    /// would fail for a reason that has nothing to do with the rule under test.
    func emit(_ level: MemoryPressureLevel) async {
        for _ in 0..<400 {
            if let continuation {
                continuation.yield(level)
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Whether the watcher released this source — the teardown half of the ownership rule.
    func stop() {
        continuation?.finish()
        continuation = nil
        didStop = true
    }
}

/// Thrown when a background watch never reacted, so the failure says which half broke rather than
/// passing quietly.
struct WatchDidNotReact: Error {}

/// Waits for something a detached task does, with a ceiling.
///
/// Bounded on purpose: a watch that never reacts must fail the test, not hang the suite.
func waitUntil(
    timeoutMilliseconds: Int = 4000,
    _ condition: @escaping @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int64(timeoutMilliseconds)))
    while !condition() {
        if ContinuousClock.now > deadline { throw WatchDidNotReact() }
        try await Task.sleep(for: .milliseconds(5))
    }
}
