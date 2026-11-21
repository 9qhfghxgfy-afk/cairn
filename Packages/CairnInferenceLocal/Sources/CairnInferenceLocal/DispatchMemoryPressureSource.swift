#if canImport(Darwin)
import Dispatch
import Foundation

/// The system's own memory-pressure dispatch source, as a stream of typed levels.
///
/// This is kept beside `SystemMemoryPressureSource` rather than replacing it, for honesty: UIKit's
/// memory-warning notification is the signal iOS is documented to send an app, and it carries no
/// severity. A dispatch source registered against `DispatchSource.MemoryPressureEvent` carries one —
/// `.warning` and `.critical` — and is the only way this app can tell "the system would like some
/// memory back" from "this process is about to be taken". Whether iOS delivers a `.critical` event to
/// a foreground app cannot be verified from a Windows machine, so both sources run and neither is
/// trusted alone; a flush is idempotent, so a warning arriving twice costs nothing.
///
/// Ownership is the point of this type. A dispatch source stops delivering events the moment the
/// object that made it goes away, so a source created inside a closure and dropped is a watcher that
/// silently stops working. The actor holds both sources as its own state, which means whoever owns
/// the actor — the app, for the life of the process — is what keeps them alive, and `stop()` is the
/// one place they are cancelled.
public actor DispatchMemoryPressureSource: MemoryPressureObserving {
    private let queue = DispatchQueue(label: "app.cairn.ondevice.memory-pressure", qos: .utility)
    // Written with explicit `any`: in Apple's Dispatch overlay these source types are **protocols**
    // (`DispatchSourceMemoryPressure : DispatchSourceProtocol, Sendable`, bridged from
    // `OS_dispatch_source_memorypressure`), not classes, and `makeMemoryPressureSource` hands back that
    // existential. Swift 6's `ExistentialAny` therefore rejects the bare name as a type; the concrete
    // subclass behind it stays private to Dispatch, which is also why nothing here can hold a class type.
    private var warningSource: (any DispatchSourceMemoryPressure)?
    private var criticalSource: (any DispatchSourceMemoryPressure)?
    /// Once stopped, stopped for good. A source that could be recreated after teardown would outlive the
    /// object that owns its system resources, which is the failure this type exists to avoid.
    private var isStopped = false
    /// Which `memoryPressureSignals()` call the held sources belong to, so a stream being dropped cannot
    /// cancel a pair that a later call installed.
    private var generation = 0

    public init() {}

    /// Installs one source per severity, with disjoint masks, so which source fired *is* the level and
    /// the handler needs no shared state to work it out.
    public func memoryPressureSignals() -> AsyncStream<MemoryPressureLevel> {
        guard !isStopped else {
            // Stopped means stopped. A watcher that could be restarted after `stop()` would be holding a
            // system source past the lifetime of whoever asked for it.
            return AsyncStream { $0.finish() }
        }
        cancelSources()
        generation += 1
        let taken = generation
        let (stream, continuation) = AsyncStream<MemoryPressureLevel>.makeStream()
        warningSource = Self.makeSource(
            eventMask: [.warning], level: .warning, queue: queue, into: continuation
        )
        criticalSource = Self.makeSource(
            eventMask: [.critical], level: .critical, queue: queue, into: continuation
        )
        // Whoever drops the stream also drops the sources: a system object nobody is listening to is
        // still a system object. The hop back into the actor is a task because `onTermination` is
        // synchronous, and the generation is re-checked there so a late cancellation cannot take a pair
        // that a later call installed.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.cancelSources(ifGeneration: taken) }
        }
        return stream
    }

    /// Cancels both sources and refuses to install another pair. Safe to call more than once, and safe to
    /// call on sources that never fired: `cancel()` on a cancelled source is a no-op, and a watcher torn
    /// down at app termination takes this path whether or not anything was ever delivered.
    public func stop() {
        isStopped = true
        cancelSources()
    }

    private func cancelSources(ifGeneration: Int) {
        guard ifGeneration == generation else { return }
        cancelSources()
    }

    private func cancelSources() {
        warningSource?.cancel()
        warningSource = nil
        criticalSource?.cancel()
        criticalSource = nil
    }

    private static func makeSource(
        eventMask: DispatchSource.MemoryPressureEvent,
        level: MemoryPressureLevel,
        queue: DispatchQueue,
        into continuation: AsyncStream<MemoryPressureLevel>.Continuation
    ) -> any DispatchSourceMemoryPressure {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: eventMask, queue: queue)
        // Captures the continuation and a level value only — no model content, no path, no size.
        source.setEventHandler { continuation.yield(level) }
        source.resume()
        return source
    }
}
#endif
