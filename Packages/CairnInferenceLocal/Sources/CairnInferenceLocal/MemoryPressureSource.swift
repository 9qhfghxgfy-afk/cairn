import Foundation

/// A stream of memory-pressure levels, so the eviction path can be driven from a test.
///
/// Levels rather than bare signals, because the two severities call for different answers: a warning
/// is answered by handing buffers back, a critical event by releasing a model. A source that cannot
/// tell them apart can only ever answer at one severity, and the app would then be either jumpy or
/// deaf depending on which one it guessed.
public protocol MemoryPressureObserving: Sendable {
    func memoryPressureSignals() async -> AsyncStream<MemoryPressureLevel>

    /// Releases whatever system object this source holds. A source that owns none needs nothing, so
    /// the default is empty; a source built on a dispatch source overrides this, because whoever made
    /// that source is responsible for cancelling it.
    func stop() async
}

public extension MemoryPressureObserving {
    func stop() async {}
}

/// The system's own memory-pressure notification.
///
/// The notification name is spelled rather than imported from UIKit: this package is built and
/// tested on the macOS host, and importing UIKit there would make the eviction policy untestable
/// off a device. The name is the same one UIKit posts.
/// Holds the notification token so the `@Sendable` termination handler can hand it back. The
/// protocol type is not `Sendable`, so it travels in a box whose only mutation happens once, on one
/// thread, before the handler can run.
private final class ObserverBox: @unchecked Sendable {
    var token: (any NSObjectProtocol)?
}

public struct SystemMemoryPressureSource: MemoryPressureObserving {
    public static let notificationName = Notification.Name(
        "UIApplicationDidReceiveMemoryWarningNotification"
    )

    public init() {}

    public func memoryPressureSignals() async -> AsyncStream<MemoryPressureLevel> {
        AsyncStream { continuation in
            let center = NotificationCenter.default
            let box = ObserverBox()
            box.token = center.addObserver(
                forName: Self.notificationName,
                object: nil,
                queue: nil
            ) { _ in
                // UIKit posts one severity, and that severity is a warning by name: the app is asked
                // to free what it can spare, not told it is about to be taken. Reported as what it is,
                // never promoted to critical to make the app react harder.
                continuation.yield(.warning)
            }
            continuation.onTermination = { _ in
                if let token = box.token { center.removeObserver(token) }
            }
        }
    }
}
