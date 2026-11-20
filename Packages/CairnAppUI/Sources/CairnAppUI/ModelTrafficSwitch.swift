import Foundation
import CairnChatDomain

/// The switch that decides whether model weights may leave the device, reached through rather than
/// copied.
///
/// The acknowledgement lives in `AppSettings`, which one object owns and writes. A view model that kept
/// its own copy of it would drift the moment the Settings screen moved it, and the failure mode is the
/// worst one available: a Download button that believes it is allowed and starts a request nobody agreed
/// to. Reading through a getter every time makes that unrepresentable.
///
/// Both closures are `@MainActor`, which is also why the struct can honestly call itself Sendable: nothing
/// reachable through it is ever touched off the main actor. The downloads that consult it happen on this
/// actor, and the bytes that follow move inside the downloader, where they already do.
public struct ModelTrafficSwitch: @unchecked Sendable {
    public var isGranted: @MainActor () -> Bool
    public var setGranted: @MainActor (Bool) -> Void

    public init(
        isGranted: @escaping @MainActor () -> Bool,
        setGranted: @escaping @MainActor (Bool) -> Void
    ) {
        self.isGranted = isGranted
        self.setGranted = setGranted
    }

    /// Previews and tests: an in-memory switch, with nothing behind it.
    ///
    /// Deliberately **not** `@MainActor`. A non-isolated reference handed into a `@MainActor` closure is
    /// "sending 'box' risks causing data races" (CI run 44682235454), and making the cell main-actor-isolated
    /// only moves the problem: this function is also used as a default argument, and Swift checks default
    /// arguments in a nonisolated context, so a `@MainActor` factory would fail there instead. The cell is
    /// therefore made genuinely thread-safe, which is the claim `@unchecked Sendable` has to be able to keep.
    public static func memory(granted: Bool = false) -> ModelTrafficSwitch {
        let box = TrafficBox(granted: granted)
        return ModelTrafficSwitch(
            isGranted: { box.read() },
            setGranted: { box.write($0) }
        )
    }
}

/// A reference cell so `memory(granted:)` can be mutated through the closures it hands back.
///
/// Every reader today is on the main actor, but the closures escape, so the cell cannot rely on that: it
/// locks. An unchecked `Sendable` claim built on "nobody will call this from elsewhere" is the kind that
/// breaks silently when someone does.
private final class TrafficBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(granted: Bool) { self.value = granted }

    func read() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func write(_ granted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = granted
    }
}
