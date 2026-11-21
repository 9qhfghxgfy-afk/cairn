import CairnChatDomain
import Foundation

/// The ceiling on the runtime's Metal buffer pool, and the figure it scales down to under pressure.
///
/// A local runtime does not return freed buffers to iOS when a tensor goes away. It parks them in a
/// pool for the next allocation of a similar size, which is fast on a Mac and fatal on a phone: the
/// pool is *dirty internal* memory in a jetsam report, counted against the app and not purgeable by
/// the system at all. mlx-swift's own memory article says the default pool ceiling is the runtime's
/// whole memory limit — 1.5× the device's recommended working set — and adds, pointedly, that
/// "adjusting the cache limit is especially advantageous on devices with memory limits (e.g. iOS
/// devices where jetsam limits apply)". The article's own worked example for LLM evaluation is
/// 20 MiB.
///
/// So the ceiling here is small and the floor is smaller, and the number scales with the headroom
/// this process actually has rather than being one constant for every phone:
///
/// - unknown headroom → the **floor**, because an unmeasured budget is not a licence;
/// - a measured reading → `min(ceiling, max(floor, reading / 8))`, so the reading can move the pool
///   only between the two figures and can never push it past either end.
///
/// The weights are the big allocation and they are priced by `MLXLoadPreflight`; this number is only
/// the pool that accumulates *beside* them, which is why it is tens of megabytes and not hundreds.
public enum MLXMemoryBudget {
    /// The most pool this app will ever hold, whatever a phone reports as free.
    ///
    /// 32 MiB, which sits between mlx-swift's own 20 MiB worked example and the headroom a 4-bit
    /// build needs for its intermediates. Raising this is a one-line change, and the trade is fixed
    /// and known: a bigger pool reuses more buffers and costs more dirty memory beside the weights.
    public static let cacheLimitCeilingBytes: Int = 32 * 1024 * 1024

    /// The least pool worth having. Zero is legal and smallest, but it means no buffer is ever
    /// reused, so every token re-allocates; eight megabytes keeps a turn moving without holding
    /// anything a jetsam kill cannot afford.
    public static let cacheLimitFloorBytes: Int = 8 * 1024 * 1024

    /// The pool ceiling to ask for, given the headroom reading at load time.
    ///
    /// One eighth of the reading, clamped **both ways** — `min(ceiling, max(floor, reading / 8))`. On
    /// an 8 GB iPhone with roughly a gigabyte of usable headroom that lands on the ceiling; on a phone
    /// that has already been squeezed it shrinks toward the floor instead of adding to the pressure.
    /// A reading too small to yield even one byte of share is the most squeezed case there is, so it
    /// takes the floor and never the ceiling.
    public static func cacheLimitBytes(headroomBytes: Int64?) -> Int {
        guard let headroom = headroomBytes, headroom > 0 else {
            return cacheLimitFloorBytes
        }
        // Bounded in the wide type before it narrows. `share` can be absurd on a Mac, and after the
        // clamp it can only be the floor or the ceiling, so the `Int` conversion cannot trap.
        let share = headroom / 8
        let bounded = min(Int64(cacheLimitCeilingBytes), max(Int64(cacheLimitFloorBytes), share))
        return Int(bounded)
    }
}
