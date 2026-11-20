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
    public static func memory(granted: Bool = false) -> ModelTrafficSwitch {
        let box = TrafficBox(granted: granted)
        return ModelTrafficSwitch(
            isGranted: { box.granted },
            setGranted: { box.granted = $0 }
        )
    }
}

/// A reference cell so `memory(granted:)` can be mutated through the closures it hands back. Touched only
/// from the main actor, which is what its only two callers are.
private final class TrafficBox {
    var granted: Bool
    init(granted: Bool) { self.granted = granted }
}
