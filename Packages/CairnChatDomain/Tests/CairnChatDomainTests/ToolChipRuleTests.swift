import Foundation
import XCTest
@testable import CairnChatDomain

/// A registry entry that says it is a web tool, with no networking behind it.
///
/// The real handlers live in `CairnProviderRemote`, which this module may not import, and the app-layer
/// factory that builds them needs a Keychain and a window. What the domain has to answer is only "what
/// does a turn offer when a web tool is registered", and that is a question about the definition.
struct StubWebTool: ToolExecuting {
    var name: String
    var networkClass: NetworkClass = .publicInternet

    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            blurb: "Searches for \(name) and returns what it finds.",
            parameters: ToolParameterSchema(
                properties: ["query": ToolParameter(kind: .string, description: "What to look for.")],
                required: ["query"]
            ),
            networkClass: networkClass
        )
    }

    func execute(_ call: ToolCall, context: ToolExecutionContext) async throws -> ToolOutcome {
        throw ToolFailure(.failed, detail: "Test double; nothing runs.")
    }
}

/// The composer's `Tools` chip: what one tap means, and what the session does with it.
///
/// The rule under test is the one the phone showed broken. A tap on the chip is a decision about this
/// conversation, and nothing — not the backend's declared capability, not an unanswered disclosure about
/// a public service — may swallow it. A backend with no native tool calling is still given the tools,
/// through `PromptToolProtocol`.
@MainActor
final class ToolChipRuleTests: XCTestCase {

    private func registry() -> ToolRegistry {
        ToolRegistry(tools: [
            CalculatorTool(),
            StubWebTool(name: BuiltInTool.webSearch),
            StubWebTool(name: BuiltInTool.webFetch),
        ])
    }

    /// A session on an engine that declares no native tool calling — the shape a plain Ollama or
    /// llama.cpp server really is.
    private func session(
        webToolsReleased: Bool,
        engine: RecordingEngine = RecordingEngine()
    ) throws -> (ChatSessionModel, EphemeralStore, RecordingEngine) {
        let store = EphemeralStore()
        let conversation = try store.createConversation(
            title: "New chat", mode: .onDeviceOnly, config: ChatConfig(), isTemporary: true
        )
        let model = ChatSessionModel(conversation: conversation, store: store, providers: [engine])
        model.toolRegistry = registry()
        model.outboundWebAllowed = webToolsReleased
        model.contextEnvironment = ContextEnvironment(
            clock: .pinned(iso8601: "2026-11-19T09:00:00Z", timeZone: "UTC"),
            device: DeviceContext(platformName: "iOS", languageCode: "en", regionCode: "US")
        )
        return (model, store, engine)
    }

    func testATapAlwaysArmsAndNeverAsksPermissionFirst() {
        // The acknowledgement is a question asked alongside the tap, not a toll the tap has to pay.
        XCTAssertEqual(
            ToolChipRule.tap(chipIsUp: false, outboundWebAllowed: false),
            .arm(asksAboutWeb: true)
        )
        XCTAssertEqual(
            ToolChipRule.tap(chipIsUp: false, outboundWebAllowed: true),
            .arm(asksAboutWeb: false)
        )
        XCTAssertEqual(ToolChipRule.tap(chipIsUp: true, outboundWebAllowed: false), .disarm)
        XCTAssertEqual(ToolChipRule.tap(chipIsUp: true, outboundWebAllowed: true), .disarm)
    }

    /// The trap the chip fell into: the value written on a tap was the **shipped** set, whose chip flag is
    /// down. The tap was handled, the write landed, and the chip stayed unfilled — so the fix is not the
    /// branch, it is writing a value that means "up".
    func testTheShippedDefaultIsNotTheArmedState() {
        XCTAssertFalse(
            ToolToggleSet.default.isEnabled,
            "a fresh chat ships with the chip down, so `.default` can never mean \"armed\""
        )
        XCTAssertTrue(ToolToggleSet.armed.isEnabled, "one tap has to write a chip that is up")
        XCTAssertEqual(ToolToggleSet.armed.enabledToolNames, BuiltInTool.allNames)
        XCTAssertFalse(ToolToggleSet.localOnly.includesWebTools)
        XCTAssertTrue(ToolToggleSet.localOnly.isEnabled, "\"not the internet\" is still a working chip")
    }

    /// The chip's whole state is `toolToggle.isEnabled`, and arming it is one write, with no capability
    /// consulted anywhere on the path.
    func testArmingTheChipWritesThroughEvenOnANoToolsBackend() throws {
        let (model, store, engine) = try session(webToolsReleased: false)
        XCTAssertFalse(engine.capabilities.toolCalling, "this backend says it cannot call tools")
        XCTAssertFalse(model.conversation.config.toolToggle.isEnabled, "a fresh chat ships disarmed")

        model.setTools(.armed)

        XCTAssertTrue(model.conversation.config.toolToggle.isEnabled, "the tap armed the chat")
        XCTAssertEqual(
            try store.conversation(id: model.conversation.id)?.config.toolToggle,
            ToolToggleSet.armed,
            "and the chip survives a relaunch"
        )
    }

    /// Arming a chat on a backend with no native calling still offers the tools — through the prompt
    /// protocol. Capability chooses the dialect, never whether the user gets tools.
    func testAPromptProtocolBackendIsStillOfferedTheTools() throws {
        let (model, _, engine) = try session(webToolsReleased: false)
        model.setTools(.armed)
        let provider = try XCTUnwrap(model.activeProvider)

        let route = model.toolRouting(for: provider)
        XCTAssertTrue(route.offersTools, "an armed chat offers tools on any backend")
        XCTAssertEqual(route.format, .prompt, "no native calling means the prompt protocol, not no tools")

        let offered = route.selection(withinWordBudget: .max) {
            $0.split(whereSeparator: \.isWhitespace).count
        }
        XCTAssertFalse(offered.isEmpty, "the offer is not empty just because the backend is plain")
        XCTAssertTrue(offered.definitions.contains { $0.name == BuiltInTool.calculator })
        XCTAssertFalse(
            offered.definitions.contains { $0.name == BuiltInTool.webSearch },
            "the web half stays withheld until the acknowledgement is up"
        )
    }

    func testTheAcknowledgementReleasesTheWebHalf() throws {
        let (model, _, _) = try session(webToolsReleased: true)
        model.setTools(.armed)
        let provider = try XCTUnwrap(model.activeProvider)
        let names = model.toolRouting(for: provider).offerableNames
        XCTAssertTrue(names.contains(BuiltInTool.webSearch), "released by the acknowledgement")
        XCTAssertTrue(names.contains(BuiltInTool.calculator))
    }

    /// The whole point of the chip: the tools reach the request the engine is handed, and the block that
    /// teaches the fallback protocol is in the system message with them.
    func testAnArmedChatPutsToolDefinitionsOnTheRequest() async throws {
        let (model, _, engine) = try session(webToolsReleased: true)
        model.setTools(.armed)
        model.send("What is 12 times 34?")
        for _ in 0..<500 where model.isBusy { try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertFalse(model.isBusy, "the scripted engine never finished")

        let request = try XCTUnwrap(engine.recorder.last, "the turn must reach the engine")
        XCTAssertFalse(request.tools.isEmpty, "an armed chat sends its tools with the turn")
        XCTAssertEqual(request.toolProtocol, .prompt)
        XCTAssertTrue(
            request.tools.contains { $0.name == BuiltInTool.calculator },
            "the calculator is on the wire even though the backend cannot call natively"
        )
        let system = try XCTUnwrap(request.messages.first { $0.role == .system })
        XCTAssertTrue(
            system.text.contains("<function="),
            "a prompt-protocol model has to be shown the shape of a call"
        )
        XCTAssertTrue(
            system.text.contains(BuiltInTool.calculator),
            "and told which tools it has"
        )
    }

    /// The other half of the same rule: with the chip down, nothing about tools is sent at all.
    func testADisarmedChatSendsNoToolsAndNoToolVocabulary() async throws {
        let (model, _, engine) = try session(webToolsReleased: true)
        model.setTools(.armed)
        model.setTools(.off)
        model.send("What is 12 times 34?")
        for _ in 0..<500 where model.isBusy { try await Task.sleep(nanoseconds: 2_000_000) }

        let request = try XCTUnwrap(engine.recorder.last)
        XCTAssertTrue(request.tools.isEmpty, "a chip that is down sends no tools array")
        XCTAssertEqual(request.toolProtocol, .none)
        let system = request.messages.first { $0.role == .system }?.text ?? ""
        XCTAssertFalse(system.contains("<function="), "and no tool block")
    }
}

