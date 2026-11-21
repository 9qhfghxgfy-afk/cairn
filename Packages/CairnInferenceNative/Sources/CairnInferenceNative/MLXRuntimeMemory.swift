import Foundation

#if !targetEnvironment(simulator) && canImport(MLX)
import MLX

/// The runtime's own memory levers, read and written in one place.
///
/// Three facts make these worth wrapping rather than calling inline. `Memory.cacheLimit` is the only
/// control over the buffer pool that turns a working load into a jetsam kill; `clearCache()` is the
/// only way to hand that pool back to iOS before the process is taken for holding it; and
/// `cacheMemory` is the only way to see what the pool is holding at all. All three are documented in
/// the pinned package — `Memory.cacheLimit` is a settable property, `clearCache()` "cause all cached
/// buffers to be deallocated", and the package's own iOS article says that for LLM evaluation "you
/// might allow up to 20 megabytes of buffer cache".
///
/// The whole point of the wrapper is that the calls exist in exactly one file, so a device run can be
/// argued about from here: if a cache limit is ever not applied, it is applied here or nowhere.
enum MLXRuntimeMemory {
    static var isCompiledIn: Bool { true }

    /// Caps the buffer pool **before** a load, so the first allocation is already inside the budget.
    /// Setting this after loading is what leaves a pool sized by the load itself.
    static func applyCacheLimit(_ bytes: Int) {
        MLX.Memory.cacheLimit = bytes
    }

    /// Hands every cached buffer back to the system. Idempotent and safe to call on every turn end.
    static func flushBufferCache() {
        MLX.Memory.clearCache()
    }

    /// Bytes sitting in the pool right now — typed metadata, which is what a log is allowed to carry.
    static var cacheBytes: Int { MLX.Memory.cacheMemory }

    /// Bytes held by live arrays. Read beside `cacheBytes` to tell "the model is resident" from "the
    /// pool has grown around it".
    static var activeBytes: Int { MLX.Memory.activeMemory }
}
#else
/// The shape this file must keep so the pool and the ledger compile on the simulator and in a build
/// that left the runtime out: the levers are there, they do nothing, and `isCompiledIn` says so.
enum MLXRuntimeMemory {
    static var isCompiledIn: Bool { false }

    static func applyCacheLimit(_ bytes: Int) {}

    static func flushBufferCache() {}

    static var cacheBytes: Int { 0 }

    static var activeBytes: Int { 0 }
}
#endif
