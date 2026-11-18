import XCTest
import SwiftData
import CairnChatDomain
@testable import CairnPersistence

/// What a store written before P3 does when it meets the P3 reader, read from both ends of the column.
/// The upgrade has to be additive in both directions: an old row gains nothing it never had — no run,
/// no offered list, the `Tools` chip down, statistics still shown — and a new writer must not fill a
/// missing value with something the user never chose.
@MainActor
final class ToolLegacyRowTests: XCTestCase {

    /// A node row from before P3 has neither tool column. It reads as a turn that ran no tools, not as
    /// a turn with an empty run the UI would render as a card.
    func testAPreP3NodeRowReadsWithNoToolRunAndNothingOffered() throws {
        let store = try SwiftDataStore(inMemory: true)
        let chat = try store.createConversation(
            title: "Old thread", mode: .remoteOnly, config: .default, isTemporary: false
        )
        store.context.insert(
            ChatRecord(
                id: UUID(), conversationID: chat.id, parentID: nil, roleRaw: "assistant",
                kindRaw: "plain", stateRaw: "complete", text: "An answer from before P3.",
                thinking: nil, branchIndex: 0, providerID: "ollama", modelID: "qwen3:8b",
                createdAt: Date(timeIntervalSince1970: 5), draftsJSON: nil, metricsJSON: nil
            )
        )
        try store.context.save()

        let stored = try XCTUnwrap(try store.nodes(conversationID: chat.id).first)
        XCTAssertEqual(stored.text, "An answer from before P3.")
        XCTAssertNil(stored.toolRun, "no column, so no run — and not an empty one either")
        XCTAssertTrue(stored.toolsOffered.isEmpty)
    }

    /// A chat configured before P3 has a configuration blob with no `toolToggle` key. It still decodes,
    /// keeps every knob it had, and comes back with the chip down: an upgrade may not arm a conversation
    /// for tools the user never opted into, and it may not name a single one on the wire.
    func testAPreP3ConfigurationBlobReadsWithTheToolsChipDown() throws {
        let store = try SwiftDataStore(inMemory: true)
        var modern = ChatConfig.default
        modern.persona = "Be terse."
        modern.toolToggle = .localOnly
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(modern)) as? [String: Any]
        )
        object.removeValue(forKey: "toolToggle")  // exactly what a pre-P3 build wrote
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let id = UUID()
        store.context.insert(
            ConversationRecord(
                id: id, title: "Old chat", activeLeafID: nil,
                createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2),
                modeRaw: "remoteOnly", paramsJSON: Data(), configJSON: legacy
            )
        )
        try store.context.save()

        let upgraded = try XCTUnwrap(try store.conversation(id: id))
        XCTAssertEqual(upgraded.config.persona, "Be terse.", "the knobs it did have survive")
        XCTAssertFalse(upgraded.config.toolToggle.isEnabled, "the chip is down, not inherited from a default")
        XCTAssertEqual(upgraded.config.toolToggle.enabledCount, 0)
        XCTAssertFalse(upgraded.config.toolToggle.includesWebTools)
    }

    /// The settings row a pre-P3 build wrote has no web-tools value and no statistics value. Both read
    /// as the shipped defaults: the internet stays unacknowledged, and the statistics a user had been
    /// shown stay shown. A missing column must never silently switch something off.
    func testAPreP3SettingsRowKeepsTheShippedDefaults() throws {
        let store = try SwiftDataStore(inMemory: true)
        store.context.insert(SettingsRecord(slot: 0))
        try store.context.save()

        let settings = try store.appSettings()
        XCTAssertTrue(settings.showsGenerationStats, "a row that never asked still shows the numbers")
        XCTAssertNil(settings.webTools, "there was no web-tool choice to remember")
        XCTAssertFalse(settings.outboundWebAllowed, "so nothing may leave the device")
        XCTAssertEqual(settings.defaultChatConfig.toolToggle, .default)
    }
}
