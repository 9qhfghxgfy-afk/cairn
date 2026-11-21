import Foundation
import CairnInferenceLocal
import CairnInferenceNative

/// The thing that actually puts an on-device model back out of memory.
///
/// The registry decides and this executes, and the indirection is not tidiness. The MLX provider needs
/// the registry (it asks that registry for permission to load) while the registry needs something that
/// can unload MLX — so neither can be built first, and the sink is created empty and told about the
/// provider once both exist. And one residency id names a model Cairn cannot unload at all: Apple's.
/// That has to be answered honestly rather than counted as a release, which is what the return value
/// below is for.
actor OnDeviceUnloadSink {
    private var mlxProvider: MLXNativeProvider?
    /// Release requests this sink carried out — an id, never model content, which is the same rule
    /// every log in Cairn follows. Recorded so "did anything actually go back?" is a question a test
    /// can answer instead of one a reviewer has to take on trust.
    private(set) var releaseRequests: [String] = []

    /// Tells the sink which provider it is unloading. Called once, at launch, after the provider that
    /// needs the registry has been built.
    func attach(_ provider: MLXNativeProvider) {
        mlxProvider = provider
    }

    /// Releases the named model and answers whether memory this app controls actually went back.
    ///
    /// `false` for Apple's model is the reason this returns anything: a registry told "released" about a
    /// model iOS owns would count a freeing that never happened, and every later decision priced from
    /// that count would be too confident. A deferred release — a generation still running — is reported
    /// as carried out, because the request is recorded and lands at the end of that turn.
    @discardableResult
    func unload(modelID: String) async -> Bool {
        guard modelID == MLXNativeProvider.modelID, let mlxProvider else { return false }
        await mlxProvider.unloadIfIdle()
        releaseRequests.append(modelID)
        return true
    }

    /// Warning-level pressure: buffers back, model stays resident. Reloading a multi-gigabyte build is a
    /// worse answer to a nudge than this is.
    func flushCaches() async {
        guard let mlxProvider else { return }
        await mlxProvider.flushCachesIfIdle()
    }

    /// Backgrounding. The same release path pressure uses — one verb, one record — deferred while a
    /// generation is mid-stream. Leaving the foreground is exactly when iOS starts deciding what to take,
    /// and an answer still in flight is the one thing worth finishing first.
    func unloadResidentIfIdle() async {
        await unload(modelID: MLXNativeProvider.modelID)
    }
}
