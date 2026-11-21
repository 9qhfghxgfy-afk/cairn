#if !targetEnvironment(simulator) && canImport(MLXLMCommon)
import Foundation
import MLXLMCommon

/// One container, kept across turns, and the only thing in Cairn that holds MLX weights in memory.
///
/// Before this type existed, every turn called `loadModelContainer` and threw the result away at the
/// end of the stream. That is not merely slow: each load allocates, and the runtime's pool keeps the
/// buffers the old container used, so a conversation of six turns is six generations of dead weights
/// parked in dirty memory. One container, reused, is the difference between a conversation that fits
/// and a conversation that gets the process taken.
///
/// The container is dropped in exactly two situations: the person pointed the engine at a different
/// folder (a model switch, where the old weights must leave **before** the new ones arrive or the
/// phone is asked to hold both), and a release the ledger decided was safe to take. Memory pressure
/// alone does not drop it — that goes through `MLXTurnLedger`, which knows whether a turn is running.
public actor MLXContainerPool {
    private var container: ModelContainer?
    private var loadedDirectoryPath: String?

    public init() {}

    /// The container for this folder, loaded once and reused until the folder changes.
    ///
    /// The cache limit is applied **before** the load. A pool capped after a load is a pool that has
    /// already grown to whatever that load needed.
    public func container(for directory: URL, cacheLimitBytes: Int) async throws -> ModelContainer {
        if let container, loadedDirectoryPath == directory.path {
            return container
        }
        releaseNow()
        MLXRuntimeMemory.applyCacheLimit(cacheLimitBytes)
        do {
            let loaded = try await loadModelContainer(directory: directory)
            container = loaded
            loadedDirectoryPath = directory.path
            return loaded
        } catch is CancellationError {
            releaseNow()
            throw NativeGenerationError.cancelled
        } catch let issue as NativeGenerationError {
            releaseNow()
            throw issue
        } catch {
            // A failed load is still an allocation attempt: whatever it got hold of goes back.
            releaseNow()
            throw NativeGenerationError.loadFailed
        }
    }

    /// Drops the container and hands the pool back. Safe when nothing is loaded.
    public func releaseNow() {
        container = nil
        loadedDirectoryPath = nil
        MLXRuntimeMemory.flushBufferCache()
    }

    /// Whether weights are actually held, which is what `residentModelId()` is allowed to claim.
    public var isLoaded: Bool { container != nil }
}
#else
/// The shape this file keeps for the simulator and for a build that left the runtime out: the pool
/// exists, it holds nothing, and asking it to release is a no-op — so the provider's lifecycle code
/// reads the same in both shapes.
public actor MLXContainerPool {
    public init() {}

    public func releaseNow() {}

    public var isLoaded: Bool { false }
}
#endif
