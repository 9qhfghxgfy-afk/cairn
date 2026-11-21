import Foundation

/// Watches the system's memory pressure and answers it through the registry that owns the residents.
///
/// The watcher is a value the app **stores**, and storing it is the whole point: a watcher nobody
/// holds is a task that can be torn down and a system source nobody retains, which is a memory watch
/// that quietly stopped working while the app went on believing it had one. `stop()` exists for
/// teardown and cancels both the task and each source's system object; on a device the app keeps this
/// alive for the life of the process.
///
/// Both sources run by default — UIKit's notification and the dispatch source — because neither is
/// trusted alone. The notification is the signal iOS is documented to post but carries no severity;
/// the dispatch source carries severities whose delivery to a foreground iPhone app cannot be
/// verified off-device. The overlap is harmless by construction: warning-level pressure flushes an
/// idempotent buffer cache, so the same squeeze arriving twice costs nothing.
public struct OnDeviceMemoryWatch: Sendable {
    private let task: Task<Void, Never>
    private let sources: [any MemoryPressureObserving]

    /// Starts watching. Each source is consumed on its own task inside one group, so a stream that
    /// never ends cannot starve the other, and cancelling the group reaches every one of them.
    public static func start(
        registry: OnDeviceModelRegistry,
        sources: [any MemoryPressureObserving] = OnDeviceMemoryWatch.defaultSources()
    ) -> OnDeviceMemoryWatch {
        let task = Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for source in sources {
                    group.addTask {
                        let signals = await source.memoryPressureSignals()
                        for await level in signals {
                            if Task.isCancelled { return }
                            await registry.handleMemoryPressure(level: level)
                        }
                    }
                }
            }
        }
        return OnDeviceMemoryWatch(task: task, sources: sources)
    }

    /// The sources this app watches by default: the notification every iOS build can post, plus the
    /// dispatch source that carries severities on the platforms that have one.
    public static func defaultSources() -> [any MemoryPressureObserving] {
        var listed: [any MemoryPressureObserving] = [SystemMemoryPressureSource()]
        #if canImport(Darwin)
        listed.append(DispatchMemoryPressureSource())
        #endif
        return listed
    }

    /// Cancels the watch and releases each source's system object, waiting for both to finish.
    public func stop() async {
        task.cancel()
        for source in sources { await source.stop() }
    }
}
