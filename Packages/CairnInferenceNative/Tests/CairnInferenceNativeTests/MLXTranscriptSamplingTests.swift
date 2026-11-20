import CairnChatDomain
import Foundation
import Testing

@testable import CairnInferenceNative

/// What a `GenerationRequest` becomes on the way into a local runtime, and which knobs travel with it.
///
/// Both decisions are pure string-and-value work, so both are checked here on any host rather than only
/// inside the one file that imports MLX.
struct MLXTranscriptSamplingTests {

    private func request(
        _ messages: [ChatMessagePayload]
    ) -> GenerationRequest {
        GenerationRequest(
            modelID: MLXNativeProvider.modelID, messages: messages, config: ChatConfig()
        )
    }

    // MARK: - Transcript

    @Test func rolesSurviveTheBridgeAndAToolResultIsNeverAUserTurn() {
        // A call answer stored under the user role is still a tool result — Cairn marks it with the
        // call id, and showing it as user text teaches the model that users answer their own calls.
        let roles = MLXChatTranscript.turns(for: request([
            ChatMessagePayload(role: .system, text: "Be brief."),
            ChatMessagePayload(role: .user, text: "What is 12 times 34?"),
            ChatMessagePayload(role: .assistant, text: "Working."),
            ChatMessagePayload.toolResult(callID: "call-1", text: "408"),
        ])).map(\.role)
        #expect(roles == [.system, .user, .assistant, .tool])
        #expect(MLXChatTranscript.systemText(for: request([
            ChatMessagePayload(role: .system, text: "Be brief."),
        ])) == "Be brief.")
    }

    @Test func anEmptyTurnIsDroppedRatherThanSentAsAQuestion() {
        // An empty assistant turn reads to a model as "continue from nothing"; an empty user turn is a
        // question the user never asked.
        #expect(
            MLXChatTranscript.turns(for: request([
                ChatMessagePayload(role: .user, text: "   \n "),
                ChatMessagePayload(role: .assistant, text: "kept"),
            ])) == [NativeChatTurn(role: .assistant, text: "kept")]
        )
    }

    @Test func systemTextIsReadFromTheMessagesAndNeverInvented() {
        // No system block means nil, not a default Cairn composed on the user's behalf.
        #expect(MLXChatTranscript.systemText(for: request([
            ChatMessagePayload(role: .user, text: "Hello"),
        ])) == nil)
        // One joined block, and a tool result never joins it.
        #expect(MLXChatTranscript.systemText(for: request([
            ChatMessagePayload(role: .system, text: "One."),
            ChatMessagePayload(role: .system, text: "Two."),
            ChatMessagePayload.toolResult(callID: "call-1", text: "not a system block"),
        ])) == "One.\n\nTwo.")
    }

    // MARK: - Sampling

    @Test func theDeclaredKnobsAreTheOnesTheEngineHandsOver() {
        // The configuration sheet renders from this table, so every true row must be a value
        // `parameters(for:)` actually sets on the runtime.
        let support = NativeSampling.support
        #expect(support.temperature && support.topP && support.minP && support.topK)
        #expect(support.maxTokens && support.repeatPenalty && support.repeatLastN)
        // The runtime's parameters carry no seed, and its maxKVSize is a rotating cache bound rather
        // than a window the user may pick — so neither gets a slider.
        #expect(!support.seed && !support.contextWindow)
    }

    @Test func nothingIsInventedForAKnobTheChatLeftUnset() {
        #expect(NativeSampling.resolve(.unset).isEmpty)
        let chosen = NativeSampling.resolve(SamplingConfig(temperature: 0.4, topK: 20))
        #expect(chosen.temperature == 0.4 && chosen.topK == 20)
        #expect(chosen.topP == nil && chosen.minP == nil && chosen.maxTokens == nil)
        #expect(!chosen.isEmpty)
    }

    @Test func aContextWindowTheChatSetIsNeverPassedForOne() {
        // Declared unsupported, so the sheet says so out loud instead of sending a knob that would
        // quietly change something else.
        #expect(NativeSampling.resolve(SamplingConfig(contextWindow: 4096)).isEmpty)
        #expect(
            NativeSampling.support.droppedKeys(from: SamplingConfig(contextWindow: 4096))
                == [.contextWindow]
        )
    }
}
