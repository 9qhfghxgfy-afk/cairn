import CairnChatDomain
import Foundation
import Testing

@testable import CairnInferenceNative

/// The engine listing every downloaded model on the phone, and a switch that moves the engine.
///
/// The bug these tests hold shut is the one a person sees: three models downloaded, one row in the picker,
/// and no way to change which one answers. `MLXNativeProvider` used to report a single synthetic model
/// whatever was on disk, so the chat had nothing to switch between and the phone's own state was a guess.
/// These run on the host with the runtime absent, which is the case that matters — listing and switching
/// folders must work before any weights are loaded, and a turn against a folder that is not here must be
/// refused rather than answered by whichever model happens to be resident.
struct MLXNativeModelListingTests {

    private func folder(_ repoID: String, _ format: ModelFormat = .mlx) -> NativeInstalledModel {
        NativeInstalledModel(
            id: repoID,
            displayName: repoID.split(separator: "/").last.map(String.init) ?? repoID,
            directoryURL: URL(fileURLWithPath: "/models/\(repoID)"),
            format: format,
            sizeBytes: 4_000_000_000
        )
    }

    private func provider(
        _ folders: [NativeInstalledModel],
        active: String? = nil
    ) -> MLXNativeProvider {
        MLXNativeProvider(installed: { folders }, activeModelID: active)
    }

    @Test func everyInstalledFolderIsListedInItsOwnName() async throws {
        let held = [
            folder("mlx-community/Llama-3.2-3B-Instruct-4bit"),
            folder("mlx-community/Qwen2.5-7B-Instruct-6bit"),
            folder("mlx-community/Phi-3-mini-4bit"),
        ]
        let models = try await provider(held).models()
        #expect(models.map { $0.id } == [
            "mlx-community/Llama-3.2-3B-Instruct-4bit",
            "mlx-community/Qwen2.5-7B-Instruct-6bit",
            "mlx-community/Phi-3-mini-4bit",
        ], "the picker is the phone's folder list, not one entry invented here")
        #expect(models.map { $0.displayName }
                == ["Llama-3.2-3B-Instruct-4bit", "Qwen2.5-7B-Instruct-6bit", "Phi-3-mini-4bit"])
        // Two rows differing only by name read as a duplicate; the badge says which runtime each folder's
        // own files describe.
        #expect(models.allSatisfy { $0.runtimeBadge == "MLX" })
        #expect(models.allSatisfy { $0.providerID == MLXNativeProvider.engineID })
    }

    @Test func choosingAModelMovesTheEngineRatherThanTheLabel() async throws {
        let held = [
            folder("mlx-community/Llama-3.2-3B-Instruct-4bit"),
            folder("mlx-community/Qwen2.5-7B-Instruct-6bit"),
        ]
        let engine = provider(held, active: "mlx-community/Llama-3.2-3B-Instruct-4bit")
        #expect(await engine.activeDirectory()?.lastPathComponent == "Llama-3.2-3B-Instruct-4bit")

        try await engine.selectModel("mlx-community/Qwen2.5-7B-Instruct-6bit")
        #expect(await engine.activeModelID == "mlx-community/Qwen2.5-7B-Instruct-6bit")
        #expect(await engine.activeDirectory()?.lastPathComponent == "Qwen2.5-7B-Instruct-6bit")
    }

    /// Asking for the model that is already live must not hand weights back. The session re-states its
    /// choice every time it lists models, and a switch that released each time would be a reload per
    /// screen visit.
    @Test func choosingTheModelAlreadyInUseChangesNothing() async throws {
        let held = [folder("mlx-community/Llama-3.2-3B-Instruct-4bit")]
        let engine = provider(held, active: "mlx-community/Llama-3.2-3B-Instruct-4bit")
        try await engine.selectModel("mlx-community/Llama-3.2-3B-Instruct-4bit")
        #expect(await engine.activeModelID == "mlx-community/Llama-3.2-3B-Instruct-4bit")
    }

    /// A model deleted while the chat sat open is the ordinary case, and the answer has to be typed and
    /// immediate — not a turn that fails later, and never a load attempt against a folder that is gone.
    @Test func choosingAModelThatIsNotOnThisPhoneIsRefused() async throws {
        let held = [folder("mlx-community/Llama-3.2-3B-Instruct-4bit")]
        let engine = provider(held)
        var thrown: NativeGenerationError?
        do {
            try await engine.selectModel("mlx-community/Deleted-Yesterday")
        } catch let issue as NativeGenerationError {
            thrown = issue
        }
        #expect(thrown == .modelNotInstalled)
        #expect(await engine.activeModelID == nil, "a refused switch leaves the engine where it was")
    }

    /// With the chosen folder deleted from disk, the engine falls back to what is installed instead of
    /// failing every turn — and it says which folder answered rather than claiming the missing one.
    @Test func aDeletedChosenModelFallsBackToWhatIsInstalled() async throws {
        let held = [folder("mlx-community/Newer-6bit"), folder("mlx-community/Older-4bit")]
        let engine = provider(held, active: "mlx-community/Gone-8bit")
        #expect(await engine.activeDirectory()?.lastPathComponent == "Newer-6bit")
        let models = try await engine.models()
        #expect(models.count == 2, "the listing is the folders, whatever the engine was pointed at")
    }

    /// A turn that names a model this phone does not hold is refused even though another model is
    /// installed. Answering from the resident weights instead would be the worse failure: the person asked
    /// for one model and got another, with nothing on screen to say so.
    @Test func aTurnForAModelThatIsNotInstalledIsRefused() async {
        let held = [folder("mlx-community/Llama-3.2-3B-Instruct-4bit")]
        let engine = provider(held, active: "mlx-community/Llama-3.2-3B-Instruct-4bit")
        let ask = GenerationRequest(
            modelID: "mlx-community/Deleted-Yesterday",
            messages: [ChatMessagePayload(role: .user, text: "Hello")],
            config: ChatConfig()
        )
        var thrown: NativeGenerationError?
        do {
            for try await _ in engine.stream(ask) {}
        } catch let issue as NativeGenerationError {
            thrown = issue
        } catch {
            Issue.record("unexpected error type: \(type(of: error))")
        }
        #expect(thrown == .modelNotInstalled)
    }
}
