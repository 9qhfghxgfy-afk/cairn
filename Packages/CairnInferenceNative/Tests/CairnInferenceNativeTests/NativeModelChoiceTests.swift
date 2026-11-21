import Foundation
import Testing

@testable import CairnInferenceNative

/// Which folder a phone loads when it is asked for a model, with no runtime involved.
///
/// The picker used to be unable to list more than one on-device model, so switching was impossible; the
/// resolution rule is what makes switching mean something, and it is the part worth proving — which request
/// wins, what happens when the remembered model has been deleted, and what happens when nothing is here.
struct NativeModelChoiceTests {

    private func installed(_ ids: String...) -> [NativeInstalledModel] {
        ids.map {
            NativeInstalledModel(
                id: $0,
                displayName: $0.split(separator: "/").last.map(String.init) ?? $0,
                directoryURL: URL(fileURLWithPath: "/models/\($0)")
            )
        }
    }

    @Test func anAskedForModelThatExistsWins() throws {
        let held = installed("mlx-community/Phi-3-mini-4bit", "mlx-community/Qwen2.5-7B-Instruct-6bit")
        let picked = NativeModelChoice.resolve(
            installed: held,
            requestedID: "mlx-community/Qwen2.5-7B-Instruct-6bit",
            activeID: "mlx-community/Phi-3-mini-4bit"
        )
        #expect(picked?.id == "mlx-community/Qwen2.5-7B-Instruct-6bit",
                "the model asked for is the model loaded, whatever was loaded before")
    }

    /// No request means keep what is resident. Swapping the resident model costs a reload — the weights leave
    /// memory and come back — so an unasked-for swap is never free and must not happen silently.
    @Test func withNoRequestTheResidentModelIsKept() throws {
        let held = installed("mlx-community/Phi-3-mini-4bit", "mlx-community/Qwen2.5-7B-Instruct-6bit")
        let picked = NativeModelChoice.resolve(
            installed: held,
            requestedID: nil,
            activeID: "mlx-community/Phi-3-mini-4bit"
        )
        #expect(picked?.id == "mlx-community/Phi-3-mini-4bit")
    }

    /// A deleted model is the common case: the weights go away and the phone still has to answer. Pointing
    /// at the gone folder would fail the turn, so the newest installed folder takes over.
    @Test func aDeletedResidentModelFallsBackToWhatIsInstalled() throws {
        let held = installed("mlx-community/Newer-6bit", "mlx-community/Older-4bit")
        let picked = NativeModelChoice.resolve(
            installed: held,
            requestedID: nil,
            activeID: "mlx-community/Deleted-8bit"
        )
        #expect(picked?.id == "mlx-community/Newer-6bit",
                "the caller is told which model answered rather than being left to claim one that is gone")
    }

    /// A name that is not on this phone is a mismatch, not a preference to be guesses at. Answering from
    /// another model's weights would be the worse failure: the person picked one model and got another.
    @Test func askingForSomethingNotInstalledRefusesRatherThanSubstituting() throws {
        let held = installed("mlx-community/Only-4bit")
        #expect(
            NativeModelChoice.resolve(
                installed: held, requestedID: "mlx-community/Never-Downloaded", activeID: nil
            ) == nil
        )
    }

    /// The id this provider reported before folders had names of their own is the engine, not a folder, so
    /// a conversation still carrying it means "on-device, whatever is here" rather than a miss.
    @Test func theLegacyEngineWideIdIsNoPreference() throws {
        let held = installed("mlx-community/Llama-3.2-3B-Instruct-4bit")
        #expect(
            NativeModelChoice.resolve(
                installed: held,
                requestedID: MLXNativeProvider.modelID,
                activeID: nil
            )?.id == "mlx-community/Llama-3.2-3B-Instruct-4bit"
        )
    }

    /// A blank request is "no preference", not "load the folder named space" — the chat passes whatever the
    /// node carries, and an empty string has to read as no preference rather than as a miss.
    @Test func aBlankRequestIsNoRequest() throws {
        let held = installed("mlx-community/Live-4bit")
        #expect(
            NativeModelChoice.resolve(
                installed: held, requestedID: "   ", activeID: nil
            )?.id == "mlx-community/Live-4bit"
        )
    }

    @Test func nothingInstalledIsNothingToLoad() throws {
        #expect(NativeModelChoice.resolve(installed: [], requestedID: nil, activeID: nil) == nil)
        #expect(
            NativeModelChoice.resolve(
                installed: [], requestedID: "mlx-community/Any", activeID: nil
            ) == nil
        )
    }
}
