import Foundation

/// What the app-layer memory gate answers when the quarantined runtime asks to allocate.
///
/// The gate is a seam rather than code inside the runtime module because the two halves cannot live
/// together: the arithmetic that decides whether a model fits (`MLXLoadPreflight`,
/// `MLXMemoryBudget`) is Swift 6 strict and must stay provable without a GPU, while the code that
/// spends the memory is the Swift 5 island that imports MLX. A seam is also the only shape in which
/// the decision can be tested at all — on a machine with no Metal and no jetsam limit.
public enum NativeAdmission: Sendable, Equatable {
    /// Load it, and keep the runtime's buffer pool inside `cacheLimitBytes` while doing so.
    ///
    /// The limit travels with the verdict because the two are one decision made at one moment: the
    /// headroom reading that allowed the load is the same reading that sized the pool. Handing them
    /// out separately is how a pool ends up sized for a phone that is no longer the one being loaded.
    case admit(cacheLimitBytes: Int)
    /// Do not load. `reason` is the sentence to show the person — the gate owns the words because the
    /// gate owns the measurement they come from.
    case refuse(reason: String)

    public var isAdmitted: Bool {
        if case .admit = self { return true }
        return false
    }

    /// The pool ceiling to apply, or `nil` when the load was refused.
    public var cacheLimitBytes: Int? {
        switch self {
        case .admit(let bytes): return bytes
        case .refuse: return nil
        }
    }
}

/// Permission, and its bookkeeping: a gate that only ever says yes-or-no leaks a resident model.
public protocol NativeMemoryAdmitting: Sendable {
    /// Asked immediately before weights are read. Must re-read memory every time — a headroom figure
    /// describes the moment it was taken, and a load is not the moment of the last turn.
    func admitLoading(modelDirectory: URL) async -> NativeAdmission

    /// The turn is over, so the model is no longer busy and any release deferred while it ran can
    /// land now.
    func turnFinished(modelDirectory: URL) async
}

/// The gate a build gets when nothing is wired to it.
///
/// It admits, because refusing here would report a memory problem that was never measured — and it
/// asks for a **zero** buffer pool, which mlx-swift documents as disabling buffer reuse entirely:
/// smaller and slower, and the correct posture when nobody has measured what the phone can spare. In
/// every shipping configuration the app wires the measured gate over this one, so the zero is a
/// default, not the running value.
public struct NativeAdmissionUnwired: NativeMemoryAdmitting {
    public init() {}

    public func admitLoading(modelDirectory: URL) async -> NativeAdmission {
        .admit(cacheLimitBytes: 0)
    }

    public func turnFinished(modelDirectory: URL) async {}
}
