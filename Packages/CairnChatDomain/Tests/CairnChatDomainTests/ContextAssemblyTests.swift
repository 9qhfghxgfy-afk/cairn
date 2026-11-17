import XCTest
@testable import CairnChatDomain

/// The system block is the part of a turn the user never sees unless they look for it, so the two
/// things that matter are that it is **deterministic** and that the preview is the wire. Both are
/// checked here with a pinned clock; nothing in this file reads the machine's date or timezone.
final class ContextAssemblyTests: XCTestCase {

    private var pinned: ContextEnvironment {
        ContextEnvironment(
            clock: ContextClock.pinned(iso8601: "2026-11-16T07:30:00Z", timeZone: "UTC"),
            device: DeviceContext(platformName: "iOS", languageCode: "en", regionCode: "US")
        )
    }

    private func assemble(
        _ persona: String = "You are Cairn.",
        _ toggles: ContextToggleSet = .default,
        _ format: ResponseFormatPreference = .markdown,
        turn: TurnContext = .default
    ) -> String {
        ContextAssembly.assemble(
            persona: persona, toggles: toggles, format: format,
            environment: pinned, turn: turn
        )
    }

    func testPinnedClockProducesExactDateAndTimeLines() {
        let text = assemble()
        XCTAssertTrue(text.contains("Today is Monday, 16 November 2026."), text)
        // The clock's minute is not injected by default: a block that changes every minute makes
        // every turn's system prompt different, which is why time is opt-in per chat.
        XCTAssertFalse(text.contains("The local time"), text)

        var withTime = ContextToggleSet.default
        withTime.timeAndTimezone = true
        XCTAssertTrue(
            assemble("You are Cairn.", withTime).contains("The local time is 07:30 in UTC."),
            "a pinned clock must render the pinned instant, not the machine's"
        )
    }

    /// Byte-identical, not merely equivalent: a preview that re-rendered differently from the request
    /// would be a preview that lied.
    func testSameInputsProduceByteIdenticalBlock() {
        XCTAssertEqual(assemble(), assemble())
        XCTAssertEqual(
            assemble(turn: TurnContext(onDevice: true, streaming: true)),
            assemble(turn: TurnContext(onDevice: true, streaming: true))
        )
    }

    func testPersonaLeadsAndBareConfigIsPersonaAlone() {
        let blocks = ContextAssembly.blocks(
            persona: "Answer briefly.", toggles: .off, format: .markdown,
            environment: pinned, turn: .default
        )
        XCTAssertEqual(blocks, ["Answer briefly."])
        XCTAssertEqual(ChatConfig(persona: "Answer briefly.", context: .off)
            .systemPrompt(in: pinned), "Answer briefly.")
    }

    func testTurningOneToggleOffRemovesOnlyThatBlock() {
        var withTime = ContextToggleSet.default
        withTime.timeAndTimezone = true
        var noTime = withTime
        noTime.timeAndTimezone = false
        let text = assemble("You are Cairn.", noTime)
        XCTAssertFalse(text.contains("The local time"), text)
        XCTAssertTrue(text.contains("Today is Monday, 16 November 2026."), text)
        XCTAssertTrue(text.contains("Answer in Markdown"), text)
    }

    /// A conditional toggle that is on describes nothing on a turn without the feature, so writing it
    /// would tell the model something false.
    func testConditionalBlockIsSuppressedWhenItsFeatureIsAbsent() {
        var toggles = ContextToggleSet.default
        toggles.toolGuidance = true
        toggles.imageContext = true
        XCTAssertFalse(assemble("You are Cairn.", toggles).contains("available on this turn"))
        XCTAssertFalse(assemble("You are Cairn.", toggles).contains("attached"))

        let live = TurnContext(toolsActive: true, toolNames: ["web_search"], imageCount: 2)
        let text = assemble("You are Cairn.", toggles, turn: live)
        XCTAssertTrue(text.contains("web_search"), text)
        XCTAssertTrue(text.contains("2 image(s)"), text)
    }

    /// The capability line is only written from a declared backend. With no engine selected the block
    /// is left out rather than guessed at, because a wrong capability claim is a lie to the model.
    func testCapabilityLineOnlyFromADeclaredBackend() {
        XCTAssertFalse(assemble().contains("What this turn can actually do"))
        let turn = TurnContext(
            backendLabel: "a model on a server the user runs on their own network",
            streaming: true, contextTokens: 8192
        )
        let text = assemble(turn: turn)
        XCTAssertTrue(text.contains("a model on a server the user runs on their own network"), text)
        XCTAssertTrue(text.contains("the context window is 8192 tokens"), text)
        XCTAssertTrue(text.contains("no tools are available"), text)
    }

    /// The seam the sheet renders and the stream sends: one assembled string, exactly one system
    /// message carrying it, and nothing added on the way to the wire.
    func testAssembledBlockIsTheOnlySystemMessageOnTheWire() {
        let config = ChatConfig(persona: "You are Cairn.")
        let text = config.systemPrompt(in: pinned, turn: .default)
        let payload = ChatTree.messages(for: [], systemPrompt: text)
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload.first?.role, .system)
        XCTAssertEqual(payload.first?.text, text, "the preview text is the wire text, byte for byte")

        let empty = ChatTree.messages(for: [], systemPrompt: "   \n  ")
        XCTAssertTrue(empty.isEmpty, "whitespace-only context injects nothing")
    }
}
