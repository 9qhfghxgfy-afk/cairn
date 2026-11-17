import Foundation

/// A stream of memory-pressure signals, so the eviction path can be driven from a test.
public protocol MemoryPressureObserving: Sendable {
    func memoryPressureSignals() -> AsyncStream<Void>
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

    public func memoryPressureSignals() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = NotificationCenter.default
            let box = ObserverBox()
            box.token = center.addObserver(
                forName: Self.notificationName,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(())
            }
            continuation.onTermination = { _ in
                if let token = box.token { center.removeObserver(token) }
            }
        }
    }
}
