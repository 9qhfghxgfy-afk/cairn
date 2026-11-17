import CairnChatDomain
import Foundation

#if !targetEnvironment(simulator) && canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

/// The only place in Cairn that touches MLX.
///
/// Everything above this type is Swift 6 strict; this file is Swift 5, and the boundary the app
/// sees is the actor in `MLXNativeProvider`. Weight loading and generation happen on a real
/// device only: Metal is not present on the simulator, so the whole call is compiled out there
/// rather than attempted and failed at runtime.
///
/// HONEST GAP: the exact 3.32.3 call shapes below (a `ModelContainer` built from a local folder,
/// `generate(input:generate:)`) were written against the package's published usage notes and are
/// NOT verified from this machine, because this dependency is compiled in CI with the skip hatch
/// set. They are confined to this file on purpose: a correction there cannot move anything else.
#if !targetEnvironment(simulator) && canImport(MLXLLM) && canImport(MLXLMCommon)
enum MLXNativeEngine {
    static let isCompiledIn = true

    /// Streams one turn from weights already on disk. Cairn downloads and verifies the files
    /// itself, so this loads a folder rather than reaching for the hub — there is no second
    /// downloader here, and nothing leaves the device during generation.
    static func generate(
        system: String?,
        prompt: String,
        modelDirectory: URL,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw NativeGenerationError.modelNotInstalled
        }
        let configuration = ModelConfiguration(modelFolder: modelDirectory, modelRepo: nil)
        let container = try await LLMModelFactory().loadModelContainer(configuration: configuration)

        let input = UserInput(
            chat: ChatMessage(role: .user, content: prompt, image: nil),
            format: UserInputFormat { instructions in
                instructions + (system.map { "\n" + $0 } ?? "")
            }
        )
        do {
            try await container.generate(input: input, generate: { token, _, _ in
                onToken(token)
                return CompleteUpdate.isRunning
            })
        } catch is CancellationError {
            throw NativeGenerationError.cancelled
        } catch {
            throw NativeGenerationError.generationFailed
        }
    }
}
#else
/// The shape this file must keep so the provider compiles identically on the simulator and in a
/// build that skipped the runtime: the answer is always "not here", and it is always typed.
enum MLXNativeEngine {
    static let isCompiledIn = false

    static func generate(
        system: String?,
        prompt: String,
        modelDirectory: URL,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        if NativeRuntimeBuild.isSimulatorBuild {
            throw NativeGenerationError.runtimeUnavailableOnSimulator
        }
        throw NativeGenerationError.runtimeExcludedFromThisBuild
    }
}
#endif
