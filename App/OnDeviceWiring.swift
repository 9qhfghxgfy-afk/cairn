import Foundation
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
    static func engines() -> [any InferenceProvider] {
        [FoundationModelsProvider(), mlxProvider()]
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
    private static func mlxProvider() -> MLXNativeProvider {
        MLXNativeProvider(directoryResolver: { MLXModelDiscovery.installedDirectory() })
    }

    /// A memory warning releases the resident model rather than being noticed and ignored. iOS
    /// kills a process that holds on, and a killed app loses the chat the user was writing.
    static func startMemoryWatch(_ registry: OnDeviceModelRegistry) -> Task<Void, Never> {
        let source = SystemMemoryPressureSource()
        return Task.detached(priority: .background) {
            for await _ in source.memoryPressureSignals() {
                await registry.handleMemoryPressure()
            }
        }
    }
}
