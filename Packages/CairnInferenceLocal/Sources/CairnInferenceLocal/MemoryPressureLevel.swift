import Foundation

/// How hard the system is pushing on this process's memory, and what each level is allowed to do
/// about it.
///
/// Two levels are worth distinguishing because they call for different answers. Apple's own
/// guidance for a memory-pressure handler is to release caches first and only then release what is
/// expensive to rebuild; a warning is the point at which giving buffers back is enough, and critical
/// is the point at which a model has to go. Reacting to a warning by unloading a model spends a
/// multi-gigabyte reload on a nudge; ignoring a critical event is how a jetsam kill arrives with no
/// warning at all.
public enum MemoryPressureLevel: String, Sendable, Equatable, CaseIterable {
    /// The system asked for memory back. Free what is cheap to remake; keep what is not.
    case warning
    /// The process is close to being taken. Release what is resident and idle, now.
    case critical
}
