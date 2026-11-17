import Foundation

/// How much memory the operating system is still willing to hand this process.
///
/// `os_proc_available_memory()` is a **point-in-time** reading, not a budget for a whole session:
/// it reflects the footprint that is free *right now*. Everything that consumes it therefore
/// re-reads it at decision time rather than caching a number.
///
/// A free Apple ID build has no increased-memory entitlement, so the number this returns is the
/// real ceiling for the shipped app and M3 must fit inside it.
public protocol MemoryReading: Sendable {
    /// Bytes the process may still allocate, or `nil` when the platform declines to say.
    func availableMemoryBytes() -> Int64?
}

/// The platform reading. On macOS this reports no pressure-based ceiling and returns `nil`, which
/// callers must treat as "unknown" rather than as "unlimited".
public struct SystemMemoryReading: MemoryReading {
    public init() {}

    public func availableMemoryBytes() -> Int64? {
        // The budget API is an iOS-family call. There is no equivalent on macOS, so a host build
        // reports "unknown" rather than inventing a ceiling — an invented ceiling would let the
        // estimator claim a fit that was never measured.
        #if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        let raw = os_proc_available_memory()
        guard raw > 0 else { return nil }
        return Int64(exactly: raw)
        #else
        return nil
        #endif
    }
}

/// A fixed reading, so the estimator and the eviction policy are unit-testable with no device.
public struct FixedMemoryReading: MemoryReading {
    private let bytes: Int64?

    public init(bytes: Int64?) {
        self.bytes = bytes
    }

    public func availableMemoryBytes() -> Int64? { bytes }
}
