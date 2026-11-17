import XCTest
@testable import CairnChatDomain

/// Shared fixtures for the session-level streaming tests.
@MainActor
enum SessionHarness {

    static func makeSession(
        provider: MockStreamingProvider = .instant,
        thinkingEnabled: Bool = true,
        temporary: Bool = true
    ) throws -> (ChatSessionModel, EphemeralStore) {
        let store = EphemeralStore()
        let conversation = try store.createConversation(
            title: "New chat",
            mode: .onDeviceOnly,
            config: ChatConfig(thinkingEnabled: thinkingEnabled),
            isTemporary: temporary
        )
        let model = ChatSessionModel(conversation: conversation, store: store, providers: [provider])
        return (model, store)
    }

    /// The mock streams asynchronously, so tests yield until the turn settles.
    static func settle(_ model: ChatSessionModel, timeoutSeconds: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while model.isBusy {
            if Date() > deadline {
                XCTFail("stream did not settle within \(timeoutSeconds)s")
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Waits until at least one content chunk has landed.
    static func awaitSomeContent(_ model: ChatSessionModel, maxTicks: Int = 60) async {
        var ticks = 0
        while model.accumulator.text.isEmpty, ticks < maxTicks {
            ticks += 1
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
