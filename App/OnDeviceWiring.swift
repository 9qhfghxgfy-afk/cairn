import Foundation
import SwiftUI
import CairnChatDomain
import CairnInferenceLocal
import CairnInferenceNative

/// The on-device half of the app's wiring, kept out of `CairnApp` so the launch file stays short.
///
/// Both engines are handed over as `InferenceProvider`, so nothing above this file can tell that
/// one of them is Swift 5 with C++ behind it. The report is read from what the build actually
/// contains and what the device actually supports — never assumed: a phone that cannot run the
/// Apple model is told so in the runtime's own words, and a build that left MLX out says that too.
enum OnDeviceWiring {
    /// The engines that need no server. Both are `.onDevice`, so neither earns the outbound badge
    /// and neither needs the network opt-in.
    ///
    /// Async, because these three objects each need one of the others and none can be built first: the
    /// MLX provider asks the registry for permission to load, the registry releases through the sink,
    /// and the sink can only be told about a provider that already exists. Attaching the provider to the
    /// sink is the hop that closes the loop, and it is the only place the three meet.
    ///
    /// - Parameters:
    ///   - registry: what counts as resident in this process. The Apple model makes room through it; the
    ///     MLX engine loads through it.
    ///   - sink: the object that can actually put MLX back out of memory, which the registry's release
    ///     path points at.
    static func engines(
        registry: OnDeviceModelRegistry,
        sink: OnDeviceUnloadSink
    ) async -> [any InferenceProvider] {
        let mlx = MLXNativeProvider(
            directoryResolver: { MLXModelDiscovery.installedDirectory() },
            admission: OnDeviceMemoryAdmission(registry: registry)
        )
        await sink.attach(mlx)
        return [FoundationModelsProvider(residency: registry), mlx]
    }

    static func report() -> OnDeviceEngineReport {
        let apple = AppleModelAvailabilityReader.current()
        let mlx = mlxProvider().runtimeAvailability
        return OnDeviceEngineReport(
            appleModel: OnDeviceEngineState(
                name: "Apple model",
                status: apple.reasonText,
                isUsable: apple.isUsable
            ),
            mlx: OnDeviceEngineState(
                name: "MLX",
                status: mlx.reasonText,
                isUsable: mlx.isUsable
            )
        )
    }

    /// One MLX provider, aimed at the store rather than at a photograph of it taken at launch.
    ///
    /// A model that finishes downloading while Cairn is open is found on the next look: the Servers
    /// screen says ready and the next turn loads it, without a relaunch. The two closures are the only
    /// place this wiring touches the filesystem, so the engine still cannot reach outside its module.
    ///
    /// The report path needs no memory gate — availability is a question about the build and the folder,
    /// not about loading — so this one stays unwired, which means its turns would run with a zero buffer
    /// pool. Only the gated provider above is ever used to generate.
    private static func mlxProvider() -> MLXNativeProvider {
        MLXNativeProvider(directoryResolver: { MLXModelDiscovery.installedDirectory() })
    }

    /// The memory watch: a warning hands buffers back, a critical event releases what is idle.
    ///
    /// The returned value must be **kept** by the caller for the life of the process. A watch nobody
    /// holds is a task that can be torn down and a system source nobody retained, which is a memory
    /// watch that quietly stopped working while the app went on believing it had one.
    static func startMemoryWatch(_ registry: OnDeviceModelRegistry) -> OnDeviceMemoryWatch {
        OnDeviceMemoryWatch.start(registry: registry)
    }

    /// Leaving the foreground is the moment iOS begins deciding what to take, so the resident model
    /// goes — unless a generation is mid-stream, in which case the release lands at the end of that turn
    /// rather than tearing the answer in half.
    static func handlePhase(_ phase: ScenePhase, sink: OnDeviceUnloadSink) async {
        guard phase == .background else { return }
        await sink.unloadResidentIfIdle()
    }
}
